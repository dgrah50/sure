# Service for calculating comprehensive risk assessments for a family's portfolio.
# Analyzes concentration metrics, guardrail violations, liquidity status, and market exposure.
#
# Usage:
#   service = RiskAssessmentService.new(family)
#   assessment = service.assess
#
class RiskAssessmentService
  include Monetizable

  attr_reader :family, :user

  RISK_LEVELS = %w[low medium high critical].freeze

  def initialize(family, user: nil)
    @family = family
    @user = user || Current.user
  end

  # Returns a comprehensive risk assessment hash
  def assess
    {
      concentration: calculate_concentration_metrics,
      guardrails: check_guardrails,
      liquidity: assess_liquidity,
      exposure: calculate_exposure_metrics,
      data_quality: assess_data_quality,
      overall_risk_level: determine_overall_risk_level
    }
  end

  private

    # Calculate portfolio concentration metrics
    def calculate_concentration_metrics
      total_value = total_portfolio_value

      return default_concentration_metrics if total_value.zero?

      latest_holdings = fetch_latest_holdings
      holdings_by_value = latest_holdings.sort_by { |h| -h.amount }

      largest_holding = holdings_by_value.first
      largest_holding_pct = largest_holding ? (largest_holding.amount / total_value * 100).round(2) : 0.0

      btc_concentration_pct = calculate_btc_concentration(latest_holdings, total_value)
      top_5_pct = calculate_top_n_concentration(holdings_by_value, total_value, 5)

      {
        largest_holding_pct: largest_holding_pct,
        btc_concentration_pct: btc_concentration_pct,
        top_5_pct: top_5_pct,
        concentration_risk_level: determine_concentration_risk_level(largest_holding_pct, top_5_pct)
      }
    end

    # Check guardrail violations for the active policy
    def check_guardrails
      return [] unless active_policy_version.present?

      guardrails = active_policy_version.guardrails.enabled
      return [] if guardrails.none?

      guardrails.map { |guardrail| check_single_guardrail(guardrail) }
    end

    # Assess liquidity status (cash position)
    def assess_liquidity
      total_value = total_portfolio_value
      return default_liquidity_metrics if total_value.zero?

      cash_value = total_cash_value
      cash_pct = (cash_value / total_value * 100).round(2)

      minimum_required = calculate_cash_minimum
      status = determine_liquidity_status(cash_pct, minimum_required)

      {
        cash_pct: cash_pct,
        minimum_required: minimum_required,
        status: status
      }
    end

    # Calculate market exposure metrics (high-beta exposure)
    def calculate_exposure_metrics
      latest_holdings = fetch_latest_holdings
      total_value = total_portfolio_value

      return { high_beta_pct: 0.0 } if total_value.zero? || latest_holdings.none?

      high_beta_value = latest_holdings.sum do |holding|
        high_beta_security?(holding.security) ? holding.amount : 0
      end

      high_beta_pct = (high_beta_value / total_value * 100).round(2)

      { high_beta_pct: high_beta_pct }
    end

    # Assess data quality for risk calculations
    def assess_data_quality
      summary = family.data_quality_summary

      return default_data_quality_metrics unless summary.present?

      {
        overall_score: summary.overall_score,
        issues_count: count_data_quality_issues(summary)
      }
    end

    # Determine overall risk level based on all factors
    def determine_overall_risk_level
      concentration = calculate_concentration_metrics
      liquidity = assess_liquidity
      data_quality = assess_data_quality

      scores = []

      # Concentration risk scoring
      scores << case concentration[:concentration_risk_level]
                when "critical" then 3
                when "high" then 2
                when "medium" then 1
                else 0
                end

      # Guardrail violation scoring
      guardrail_results = check_guardrails
      critical_violations = guardrail_results.count { |g| g[:status] == "violation" && g[:severity] == "critical" }
      warning_violations = guardrail_results.count { |g| g[:status] == "violation" && g[:severity] == "warning" }

      scores << 3 if critical_violations > 0
      scores << 2 if warning_violations >= 2
      scores << 1 if warning_violations == 1

      # Liquidity risk scoring
      scores << case liquidity[:status]
                when "critical" then 3
                when "warning" then 1
                else 0
                end

      # Data quality risk scoring
      scores << if data_quality[:overall_score] < 40
                  3
                elsif data_quality[:overall_score] < 60
                  2
                elsif data_quality[:overall_score] < 75
                  1
                else
                  0
                end

      max_score = scores.max || 0

      case max_score
      when 3 then "critical"
      when 2 then "high"
      when 1 then "medium"
      else "low"
      end
    end

    # Fetch the latest holdings for each security
    def fetch_latest_holdings
      family.holdings
            .includes(:security, :account)
            .where(currency: family.currency)
            .where.not(qty: 0)
            .where(
              id: family.holdings
                        .select("DISTINCT ON (security_id) id")
                        .where(currency: family.currency)
                        .order(:security_id, date: :desc)
            )
    end

    # Calculate total portfolio value across all asset accounts
    def total_portfolio_value
      family.accounts
            .assets
            .where(status: "active")
            .sum(:balance)
            .to_d
    end

    # Calculate total cash value across accounts
    def total_cash_value
      family.accounts
            .where(status: "active")
            .sum(:cash_balance)
            .to_d
    end

    # Calculate BTC concentration percentage
    def calculate_btc_concentration(holdings, total_value)
      return 0.0 if total_value.zero?

      btc_holdings = holdings.select { |h| btc_security?(h.security) }
      btc_value = btc_holdings.sum(&:amount)

      (btc_value / total_value * 100).round(2)
    end

    # Check if a security is BTC
    def btc_security?(security)
      return false unless security.present?

      ticker = security.ticker.to_s.upcase
      ticker == "BTC" || ticker.start_with?("BTC") || ticker.include?("BITCOIN")
    end

    # Calculate top N holdings concentration
    def calculate_top_n_concentration(holdings_by_value, total_value, n)
      return 0.0 if total_value.zero?

      top_n_value = holdings_by_value.first(n).sum(&:amount)
      (top_n_value / total_value * 100).round(2)
    end

    # Determine concentration risk level
    def determine_concentration_risk_level(largest_pct, top_5_pct)
      if largest_pct > 50 || top_5_pct > 80
        "critical"
      elsif largest_pct > 25 || top_5_pct > 60
        "high"
      elsif largest_pct > 15 || top_5_pct > 40
        "medium"
      else
        "low"
      end
    end

    # Get the active policy version for the family
    def active_policy_version
      @active_policy_version ||= PolicyVersion.for_family(family).active.first
    end

    # Check a single guardrail against current portfolio state
    def check_single_guardrail(guardrail)
      result = case guardrail.guardrail_type
               when "concentration_limit"
                 check_concentration_guardrail(guardrail)
               when "single_security_limit"
                 check_single_security_guardrail(guardrail)
               when "cash_minimum"
                 check_cash_minimum_guardrail(guardrail)
               when "cash_maximum"
                 check_cash_maximum_guardrail(guardrail)
               when "sector_concentration"
                 check_sector_concentration_guardrail(guardrail)
               else
                 { passed: true, message: nil }
               end

      {
        name: guardrail.name,
        type: guardrail.guardrail_type,
        severity: guardrail.severity,
        status: result[:passed] ? "pass" : "violation",
        message: result[:message]
      }
    end

    # Check concentration limit guardrail
    def check_concentration_guardrail(guardrail)
      threshold = guardrail.threshold.to_f
      return { passed: true, message: nil } if threshold.zero?

      total_value = total_portfolio_value
      return { passed: true, message: nil } if total_value.zero?

      latest_holdings = fetch_latest_holdings
      holdings_by_value = latest_holdings.sort_by { |h| -h.amount }

      # Check largest holding concentration
      largest = holdings_by_value.first
      return { passed: true, message: nil } unless largest

      largest_pct = (largest.amount / total_value * 100).round(2)
      passed = largest_pct <= threshold

      {
        passed: passed,
        message: passed ? nil : "Largest holding (#{largest.security.ticker}) is #{largest_pct}% of portfolio, exceeding #{threshold}% limit"
      }
    end

    # Check single security limit guardrail
    def check_single_security_guardrail(guardrail)
      threshold = guardrail.threshold.to_f
      return { passed: true, message: nil } if threshold.zero?

      total_value = total_portfolio_value
      return { passed: true, message: nil } if total_value.zero?

      latest_holdings = fetch_latest_holdings

      violations = []
      latest_holdings.each do |holding|
        pct = (holding.amount / total_value * 100).round(2)
        if pct > threshold
          violations << "#{holding.security.ticker} (#{pct}%)"
        end
      end

      passed = violations.empty?

      {
        passed: passed,
        message: passed ? nil : "Securities exceeding #{threshold}% limit: #{violations.join(', ')}"
      }
    end

    # Check cash minimum guardrail
    def check_cash_minimum_guardrail(guardrail)
      minimum = guardrail.threshold.to_f
      return { passed: true, message: nil } if minimum.zero?

      total_value = total_portfolio_value
      return { passed: true, message: nil } if total_value.zero?

      cash_value = total_cash_value
      cash_pct = (cash_value / total_value * 100).round(2)
      passed = cash_pct >= minimum

      {
        passed: passed,
        message: passed ? nil : "Cash allocation of #{cash_pct}% is below minimum requirement of #{minimum}%"
      }
    end

    # Check cash maximum guardrail
    def check_cash_maximum_guardrail(guardrail)
      maximum = guardrail.threshold.to_f
      return { passed: true, message: nil } if maximum.zero?

      total_value = total_portfolio_value
      return { passed: true, message: nil } if total_value.zero?

      cash_value = total_cash_value
      cash_pct = (cash_value / total_value * 100).round(2)
      passed = cash_pct <= maximum

      {
        passed: passed,
        message: passed ? nil : "Cash allocation of #{cash_pct}% exceeds maximum limit of #{maximum}%"
      }
    end

    # Check sector concentration guardrail
    def check_sector_concentration_guardrail(guardrail)
      # Sector data is not currently stored in the security model
      # This is a placeholder for future implementation
      { passed: true, message: nil }
    end

    # Calculate required cash minimum from guardrails
    def calculate_cash_minimum
      return 0.0 unless active_policy_version.present?

      guardrail = active_policy_version.guardrails.enabled.by_type("cash_minimum").first
      return 0.0 unless guardrail.present?

      guardrail.threshold.to_f
    end

    # Determine liquidity status
    def determine_liquidity_status(cash_pct, minimum_required)
      return "pass" if minimum_required.zero?

      if cash_pct < minimum_required * 0.5
        "critical"
      elsif cash_pct < minimum_required
        "warning"
      else
        "pass"
      end
    end

    # Check if a security is considered high-beta
    def high_beta_security?(security)
      return false unless security.present?

      # High-beta sectors/indicators based on ticker patterns
      # This is a simplified heuristic - in production this would use actual beta data
      high_beta_indicators = %w[
        TSLA NVDA AMD COIN HOOD SOXL TQQQ UPRO LABU DRN BNKU FAS
      ]

      ticker = security.ticker.to_s.upcase
      high_beta_indicators.include?(ticker)
    end

    # Count data quality issues
    def count_data_quality_issues(summary)
      count = 0

      count += 1 if summary.price_freshness_score < 75
      count += 1 if summary.fx_freshness_score < 75
      count += 1 if summary.holdings_quality_score < 75

      count
    end

    # Default metrics for when data is unavailable
    def default_concentration_metrics
      {
        largest_holding_pct: 0.0,
        btc_concentration_pct: 0.0,
        top_5_pct: 0.0,
        concentration_risk_level: "low"
      }
    end

    def default_liquidity_metrics
      {
        cash_pct: 0.0,
        minimum_required: 0.0,
        status: "pass"
      }
    end

    def default_data_quality_metrics
      {
        overall_score: 100,
        issues_count: 0
      }
    end
end

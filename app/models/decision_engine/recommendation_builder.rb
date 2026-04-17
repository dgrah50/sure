# frozen_string_literal: true

class DecisionEngine::RecommendationBuilder
  REBALANCE_SEVERITY_THRESHOLDS = {
    minor: 5.0,
    moderate: 15.0,
    major: 25.0
  }.freeze

  attr_reader :policy_version

  def initialize(policy_version)
    @policy_version = policy_version
  end

  def build_recommendations!
    return [] unless policy_version.active?
    return [] unless target_percentage_valid?

    recommendations = []

    family_holdings = current_holdings_by_sleeve
    target_allocations = target_allocations_by_sleeve

    drift_metrics = calculate_drift_metrics(target_allocations, family_holdings)
    severity = rebalance_type(drift_metrics[:total_drift])

    return [] if severity == :minor && drift_metrics[:total_drift] < REBALANCE_SEVERITY_THRESHOLDS[:minor]

    trades = calculate_trades(target_allocations, family_holdings)

    return [] if trades.empty?

    total_amount = trades.sum { |t| t[:estimated_amount] }

    recommendation = policy_version.family.recommendations.create!(
      policy_version: policy_version,
      recommendation_type: "rebalance",
      title: "Portfolio Rebalance Recommended - #{severity.to_s.titleize}",
      description: build_description(drift_metrics, severity),
      status: "pending",
      details: {
        trades: trades,
        total_amount: total_amount,
        rationale: build_rationale(drift_metrics, trades),
        drift_metrics: drift_metrics
      }
    )

    recommendations << recommendation
  end

  def calculate_trades(target_allocation, current_allocation)
    trades = []
    total_portfolio_value = current_allocation.values.sum { |h| h[:value] }

    return trades if total_portfolio_value.zero?

    target_allocation.each do |sleeve_id, target|
      current = current_allocation[sleeve_id] || { value: 0, securities: {} }
      target_value = (target[:percentage] / 100.0) * total_portfolio_value
      value_diff = target_value - current[:value]

      next if value_diff.abs < 1.0

      if value_diff > 0
        trades.concat(generate_buy_trades(sleeve_id, target, current, value_diff))
      elsif value_diff < 0
        trades.concat(generate_sell_trades(sleeve_id, current, value_diff.abs))
      end
    end

    trades
  end

  def rebalance_type(severity)
    case severity
    when 0...REBALANCE_SEVERITY_THRESHOLDS[:minor]
      :minor
    when REBALANCE_SEVERITY_THRESHOLDS[:minor]...REBALANCE_SEVERITY_THRESHOLDS[:moderate]
      :moderate
    when REBALANCE_SEVERITY_THRESHOLDS[:moderate]...REBALANCE_SEVERITY_THRESHOLDS[:major]
      :major
    else
      :major
    end
  end

  private

    def family
      @family ||= policy_version.family
    end

    def target_percentage_valid?
      policy_version.target_percentage_valid?
    end

    def target_allocations_by_sleeve
      policy_version.sleeves.root.each_with_object({}) do |sleeve, allocations|
        allocations[sleeve.id] = {
          name: sleeve.name,
          percentage: sleeve.target_percentage,
          securities: sleeve_target_securities(sleeve)
        }
      end
    end

    def sleeve_target_securities(sleeve)
      if sleeve.leaf?
        { sleeve.name => sleeve.target_percentage }
      else
        sleeve.child_sleeves.each_with_object({}) do |child, securities|
          securities[child.name] = child.target_percentage
        end
      end
    end

    def current_holdings_by_sleeve
      holdings = family.holdings
        .includes(:security)
        .select("DISTINCT ON (security_id) holdings.*")
        .order(:security_id, date: :desc)

      holdings_by_sleeve = Hash.new { |h, k| h[k] = { value: 0, securities: {} } }

      holdings.each do |holding|
        sleeve_id = assign_holding_to_sleeve(holding)
        value = holding.amount_money.amount

        holdings_by_sleeve[sleeve_id][:value] += value
        holdings_by_sleeve[sleeve_id][:securities][holding.security_id] = {
          ticker: holding.ticker,
          qty: holding.qty,
          value: value,
          price: holding.price
        }
      end

      holdings_by_sleeve
    end

    def assign_holding_to_sleeve(holding)
      target_allocations = target_allocations_by_sleeve
      return target_allocations.keys.first if target_allocations.empty?

      target_allocations.keys.find { |sleeve_id| holding_matches_sleeve?(holding, sleeve_id) } ||
        target_allocations.keys.first
    end

    def holding_matches_sleeve?(holding, sleeve_id)
      sleeve = Sleeve.find_by(id: sleeve_id)
      return false unless sleeve

      target_securities = sleeve_target_securities(sleeve)
      target_securities.keys.any? { |name| name.downcase.include?(holding.security.name.to_s.downcase) } ||
        target_securities.keys.any? { |name| holding.ticker.downcase.include?(name.downcase) }
    rescue ActiveRecord::RecordNotFound
      false
    end

    def calculate_drift_metrics(target_allocations, current_allocations)
      total_value = current_allocations.values.sum { |h| h[:value] }

      return { total_drift: 0, sleeve_drifts: {}, cash_percentage: 0 } if total_value.zero?

      sleeve_drifts = {}
      total_drift = 0

      target_allocations.each do |sleeve_id, target|
        current = current_allocations[sleeve_id] || { value: 0 }
        target_value = (target[:percentage] / 100.0) * total_value
        current_value = current[:value]

        drift_percentage = target_value.zero? ? 0 : ((current_value - target_value) / target_value * 100).abs
        absolute_drift = ((current_value / total_value * 100) - target[:percentage]).abs

        sleeve_drifts[sleeve_id] = {
          sleeve_name: target[:name],
          target_percentage: target[:percentage],
          current_percentage: (current_value / total_value * 100).round(2),
          target_value: target_value.round(2),
          current_value: current_value.round(2),
          drift_percentage: drift_percentage.round(2),
          absolute_drift: absolute_drift.round(2)
        }

        total_drift += absolute_drift
      end

      cash_value = current_allocations.values.flat_map { |h| h[:securities].values }
        .select { |s| s[:ticker]&.upcase&.include?("CASH") }
        .sum { |s| s[:value] }

      {
        total_drift: total_drift.round(2),
        sleeve_drifts: sleeve_drifts,
        cash_percentage: ((cash_value / total_value) * 100).round(2),
        total_portfolio_value: total_value.round(2)
      }
    end

    def generate_buy_trades(sleeve_id, target, current, value_diff)
      trades = []
      target_securities = target[:securities]

      target_securities.each do |security_name, target_pct|
        security = find_security_by_name_or_ticker(security_name)
        next unless security

        current_qty = current.dig(:securities, security.id, :qty) || 0
        current_price = security.current_price&.amount || current.dig(:securities, security.id, :price) || 1
        next if current_price.zero?

        allocation_amount = (target_pct / 100.0) * value_diff
        shares_to_buy = (allocation_amount / current_price).floor

        next if shares_to_buy <= 0

        estimated_amount = shares_to_buy * current_price

        trades << {
          action: "buy",
          ticker: security.ticker,
          security_id: security.id,
          sleeve_id: sleeve_id,
          shares: shares_to_buy,
          estimated_price: current_price.round(2),
          estimated_amount: estimated_amount.round(2),
          rationale: "Increase #{target[:name]} allocation toward #{target_pct}% target"
        }
      end

      trades
    end

    def generate_sell_trades(sleeve_id, current, value_diff)
      trades = []
      securities = current[:securities]

      securities.each do |security_id, security_data|
        security = Security.find_by(id: security_id)
        next unless security

        current_value = security_data[:value]
        next if current_value.zero?

        current_price = security.current_price&.amount || security_data[:price] || 1
        next if current_price.zero?

        reduction_factor = [ value_diff / current[:value], 1.0 ].min
        shares_to_sell = (security_data[:qty] * reduction_factor).floor

        next if shares_to_sell <= 0

        estimated_amount = shares_to_sell * current_price

        trades << {
          action: "sell",
          ticker: security.ticker,
          security_id: security_id,
          sleeve_id: sleeve_id,
          shares: shares_to_sell,
          estimated_price: current_price.round(2),
          estimated_amount: estimated_amount.round(2),
          rationale: "Reduce #{security_data[:ticker]} position to align with target allocation"
        }
      end

      trades
    end

    def find_security_by_name_or_ticker(name)
      Security.find_by("LOWER(ticker) = LOWER(?) OR LOWER(name) = LOWER(?)", name, name) ||
        Security.find_by("LOWER(ticker) LIKE LOWER(?)", "%#{name}%") ||
        Security.find_by("LOWER(name) LIKE LOWER(?)", "%#{name}%")
    end

    def build_description(drift_metrics, severity)
      "Portfolio drift of #{drift_metrics[:total_drift]}% detected across #{drift_metrics[:sleeve_drifts].count} sleeves. " \
        "Rebalance recommended to align with policy targets. Cash position: #{drift_metrics[:cash_percentage]}%."
    end

    def build_rationale(drift_metrics, trades)
      rationale = "Portfolio has drifted #{drift_metrics[:total_drift]}% from target allocations. "

      drift_metrics[:sleeve_drifts].each do |sleeve_id, metrics|
        if metrics[:absolute_drift] > 1.0
          direction = metrics[:current_percentage] > metrics[:target_percentage] ? "overweight" : "underweight"
          rationale += "#{metrics[:sleeve_name]} is #{direction} by #{metrics[:absolute_drift]}% " \
                       "(target: #{metrics[:target_percentage]}%, current: #{metrics[:current_percentage]}%). "
        end
      end

      rationale += "Proposed trades: #{trades.count} total trades with estimated value of $#{trades.sum { |t| t[:estimated_amount] }.round(2)}."

      rationale
    end
end

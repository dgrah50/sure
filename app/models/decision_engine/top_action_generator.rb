# frozen_string_literal: true

module DecisionEngine
  # Analyzes portfolio state and generates top actions for advisors.
  # This is a lightweight PORO that follows the Rails convention of
  # keeping business logic in models rather than controllers.
  #
  # Usage:
  #   generator = DecisionEngine::TopActionGenerator.new(family)
  #   generator.generate_actions!
  #
  class TopActionGenerator
    # Configuration constants for action detection thresholds
    REBALANCE_THRESHOLD = 5.0  # 5% drift triggers rebalance recommendation
    CASH_IDLE_THRESHOLD = 10.0  # 10% cash allocation considered idle
    STALE_DATA_THRESHOLD = 24.hours
    MISSING_PRICE_THRESHOLD = 1.day
    EXPIRED_ACTION_DAYS = 30

    PRIORITY_WEIGHTS = {
      critical: 10,
      high: 8,
      medium: 6,
      low: 4,
      info: 2
    }.freeze

    def initialize(family)
      @family = family
    end

    # Main entry point: analyzes portfolio and generates all top actions
    def generate_actions!
      return unless family.present?

      actions = []

      actions.concat(detect_policy_drift)
      actions.concat(detect_rebalance_needed)
      actions.concat(detect_data_quality_issues)
      actions.concat(detect_cash_idle)
      actions.concat(detect_manual_review_flags)
      actions.concat(detect_compliance_issues)

      persist_actions(actions)
      actions
    end

    # Legacy method for backward compatibility
    def generate_all
      generate_actions!
    end

    # Removes actions that have expired (older than 30 days and not completed)
    def clear_expired_actions!
      family.top_actions.active.where("created_at < ?", EXPIRED_ACTION_DAYS.days.ago).find_each do |action|
        action.dismiss!
      end
    end

    # Calculates priority score (1-10) based on action type and severity
    def score_priority(action_type, severity)
      base_priority = case action_type
      when "compliance_issue"
        PRIORITY_WEIGHTS[:critical]
      when "rebalance_needed"
        PRIORITY_WEIGHTS[:high]
      when "policy_drift"
        PRIORITY_WEIGHTS[:high]
      when "data_quality"
        PRIORITY_WEIGHTS[:medium]
      when "cash_idle"
        PRIORITY_WEIGHTS[:low]
      when "manual_review"
        PRIORITY_WEIGHTS[:medium]
      else
        PRIORITY_WEIGHTS[:info]
      end

      severity_modifier = case severity.to_s
      when "critical"
        2
      when "warning"
        1
      when "info"
        -1
      else
        0
      end

      [[base_priority + severity_modifier, 10].min, 1].max
    end

    private

    attr_reader :family

    # Detects policy drift by comparing current allocation to target allocation
    def detect_policy_drift
      actions = []
      policy = family.policy_versions.active.first

      return actions unless policy.present? && policy.sleeves.any?

      current_allocation = calculate_current_allocation

      policy.sleeves.root.each do |sleeve|
        current_pct = current_allocation[sleeve.id] || 0
        target_pct = sleeve.target_percentage.to_f
        drift = (current_pct - target_pct).abs

        next unless drift > 1.0  # Only flag drift > 1%

        severity = drift > REBALANCE_THRESHOLD ? "critical" : "warning"

        actions << build_action(
          action_type: "policy_drift",
          title: "Policy drift detected in #{sleeve.name}",
          description: "Current allocation (#{current_pct.round(2)}%) deviates from target (#{target_pct.round(2)}%) by #{drift.round(2)}%",
          severity: severity,
          metadata: {
            sleeve_id: sleeve.id,
            sleeve_name: sleeve.name,
            current_percentage: current_pct,
            target_percentage: target_pct,
            drift_percentage: drift
          }
        )
      end

      actions
    end

    # Detects if rebalance is needed based on guardrail threshold breaches
    def detect_rebalance_needed
      actions = []
      policy = family.policy_versions.active.first

      return actions unless policy.present?

      # Check guardrails for threshold breaches
      policy.guardrails.enabled.each do |guardrail|
        case guardrail.guardrail_type
        when "drift_threshold"
          actions.concat(check_drift_guardrail(guardrail))
        when "concentration_limit"
          actions.concat(check_concentration_guardrail(guardrail))
        when "cash_minimum", "cash_maximum"
          actions.concat(check_cash_guardrail(guardrail))
        when "single_security_limit"
          actions.concat(check_security_concentration(guardrail))
        end
      end

      actions
    end

    # Detects data quality issues (stale prices, missing data, sync failures)
    def detect_data_quality_issues
      actions = []

      # Check for stale security prices
      stale_securities = family.holdings
        .joins(:security)
        .where("securities.last_synced_at < ? OR securities.last_synced_at IS NULL", MISSING_PRICE_THRESHOLD.ago)
        .distinct
        .pluck("securities.ticker", "securities.name")

      if stale_securities.any?
        actions << build_action(
          action_type: "data_quality",
          title: "Stale security prices detected",
          description: "#{stale_securities.count} securities have outdated price data",
          severity: "warning",
          metadata: {
            stale_securities: stale_securities.first(10),
            total_stale: stale_securities.count
          }
        )
      end

      # Check for recent sync failures
      failed_syncs = family.syncs.failed.where("created_at > ?", 7.days.ago)

      if failed_syncs.any?
        actions << build_action(
          action_type: "data_quality",
          title: "Recent sync failures detected",
          description: "#{failed_syncs.count} sync(s) failed in the last 7 days",
          severity: "critical",
          metadata: {
            failed_sync_count: failed_syncs.count,
            latest_error: failed_syncs.first&.error
          }
        )
      end

      # Check for holdings with unknown confidence
      unknown_confidence_holdings = family.holdings.unknown_confidence.count

      if unknown_confidence_holdings > 0
        actions << build_action(
          action_type: "data_quality",
          title: "Unverified holdings data",
          description: "#{unknown_confidence_holdings} holdings have unverified data confidence",
          severity: "info",
          metadata: {
            unknown_confidence_count: unknown_confidence_holdings
          }
        )
      end

      actions
    end

    # Detects idle cash above threshold
    def detect_cash_idle
      actions = []

      family.accounts.includes(:holdings).each do |account|
        next unless account.balance.positive?

        # Calculate cash allocation (simplified - cash is holdings without securities or depository accounts)
        cash_balance = calculate_cash_balance(account)
        next unless cash_balance.positive?

        cash_percentage = (cash_balance / account.balance) * 100

        next unless cash_percentage >= CASH_IDLE_THRESHOLD

        actions << build_action(
          action_type: "cash_idle",
          title: "Idle cash detected in #{account.name}",
          description: "#{cash_percentage.round(2)}% of account is uninvested cash",
          severity: "info",
          metadata: {
            account_id: account.id,
            account_name: account.name,
            cash_balance: cash_balance.to_f,
            cash_percentage: cash_percentage,
            total_balance: account.balance.to_f
          }
        )
      end

      actions
    end

    # Detects holdings requiring manual review (locked cost basis, security remapped)
    def detect_manual_review_flags
      actions = []

      # Holdings with locked cost basis that may need attention
      locked_holdings = family.holdings.with_locked_cost_basis
        .where("updated_at < ?", 90.days.ago)
        .count

      if locked_holdings > 0
        actions << build_action(
          action_type: "manual_review",
          title: "Locked cost basis entries need review",
          description: "#{locked_holdings} holdings with locked cost basis haven't been reviewed in 90+ days",
          severity: "info",
          metadata: {
            locked_holdings_count: locked_holdings
          }
        )
      end

      # Holdings with remapped securities
      remapped_holdings = family.holdings.select(&:security_remapped?)

      if remapped_holdings.any?
        actions << build_action(
          action_type: "manual_review",
          title: "Remapped securities need verification",
          description: "#{remapped_holdings.count} holdings have manually remapped securities",
          severity: "warning",
          metadata: {
            remapped_count: remapped_holdings.count,
            holdings: remapped_holdings.map { |h| { id: h.id, security: h.security.ticker } }
          }
        )
      end

      actions
    end

    # Detects compliance issues based on guardrails
    def detect_compliance_issues
      actions = []
      policy = family.policy_versions.active.first

      return actions unless policy.present?

      # Check critical guardrails
      policy.guardrails.enabled.critical.each do |guardrail|
        result = evaluate_guardrail(guardrail)

        unless result[:passed]
          actions << build_action(
            action_type: "compliance_issue",
            title: "Compliance violation: #{guardrail.name}",
            description: result[:message],
            severity: "critical",
            metadata: {
              guardrail_id: guardrail.id,
              guardrail_type: guardrail.guardrail_type,
              threshold: guardrail.threshold,
              actual_value: result[:actual_value]
            }
          )
        end
      end

      actions
    end

    # Helper: Calculate current allocation by sleeve
    def calculate_current_allocation
      allocation = {}
      total_value = family.holdings.sum(:amount)

      return allocation if total_value.zero?

      family.holdings.includes(:security).each do |holding|
        # Map holdings to sleeves (simplified - would need more complex logic in production)
        sleeve_id = determine_sleeve_for_holding(holding)
        allocation[sleeve_id] ||= 0
        allocation[sleeve_id] += (holding.amount / total_value) * 100
      end

      allocation
    end

    # Helper: Determine which sleeve a holding belongs to
    def determine_sleeve_for_holding(holding)
      # Simplified logic - in production would use security classification
      # and sleeve criteria to map holdings to sleeves
      policy = family.policy_versions.active.first
      return nil unless policy

      # Return first root sleeve as default (simplified)
      policy.sleeves.root.first&.id
    end

    # Helper: Calculate cash balance for an account
    def calculate_cash_balance(account)
      # Cash is typically in depository accounts or uninvested cash
      if account.is_a?(Depository)
        account.balance
      else
        # For investment accounts, assume cash is any uninvested balance
        # This is simplified - would need actual cash position from holdings
        account.balance - account.holdings.sum(:amount)
      end
    end

    # Guardrail check methods
    def check_drift_guardrail(guardrail)
      actions = []
      # Drift detection logic similar to policy_drift
      actions
    end

    def check_concentration_guardrail(guardrail)
      actions = []
      limit = guardrail.threshold.to_f

      family.holdings.includes(:security).group_by(&:security).each do |security, holdings|
        total_value = holdings.sum(&:amount)
        total_portfolio = family.holdings.sum(:amount)
        next if total_portfolio.zero?

        percentage = (total_value / total_portfolio) * 100

        next unless percentage > limit

        actions << build_action(
          action_type: "rebalance_needed",
          title: "Concentration limit exceeded: #{security.ticker}",
          description: "Position exceeds #{limit}% limit at #{percentage.round(2)}%",
          severity: guardrail.severity,
          metadata: {
            guardrail_id: guardrail.id,
            security_id: security.id,
            ticker: security.ticker,
            percentage: percentage,
            limit: limit
          }
        )
      end

      actions
    end

    def check_cash_guardrail(guardrail)
      actions = []
      threshold = guardrail.threshold.to_f

      total_balance = family.accounts.sum(:balance)
      return actions if total_balance.zero?

      total_cash = family.accounts.sum { |a| calculate_cash_balance(a) }
      cash_percentage = (total_cash / total_balance) * 100

      violated = case guardrail.guardrail_type
      when "cash_minimum"
        cash_percentage < threshold
      when "cash_maximum"
        cash_percentage > threshold
      end

      if violated
        actions << build_action(
          action_type: "rebalance_needed",
          title: "Cash allocation #{guardrail.guardrail_type == "cash_minimum" ? "below minimum" : "above maximum"}",
          description: "Cash allocation of #{cash_percentage.round(2)}% violates #{guardrail.name}",
          severity: guardrail.severity,
          metadata: {
            guardrail_id: guardrail.id,
            cash_percentage: cash_percentage,
            threshold: threshold
          }
        )
      end

      actions
    end

    def check_security_concentration(guardrail)
      actions = []
      limit = guardrail.threshold.to_f

      family.holdings.includes(:security).group_by(&:security).each do |security, holdings|
        total_value = holdings.sum(&:amount)
        next if total_value.zero?

        # Calculate as percentage of account or total portfolio
        account = holdings.first.account
        percentage = (total_value / account.balance) * 100

        next unless percentage > limit

        actions << build_action(
          action_type: "rebalance_needed",
          title: "Single security limit exceeded",
          description: "#{security.ticker} represents #{percentage.round(2)}% of #{account.name}",
          severity: guardrail.severity,
          metadata: {
            guardrail_id: guardrail.id,
            security_id: security.id,
            ticker: security.ticker,
            percentage: percentage,
            limit: limit,
            account_id: account.id
          }
        )
      end

      actions
    end

    def evaluate_guardrail(guardrail)
      # Uses guardrail's built-in check method
      case guardrail.guardrail_type
      when "drift_threshold"
        current_allocation = calculate_current_allocation
        max_drift = current_allocation.values.map { |v| (v - 100.0 / current_allocation.size).abs }.max
        guardrail.check(max_drift || 0, { sleeve_name: "Portfolio" })
      when "cash_minimum", "cash_maximum"
        total_balance = family.accounts.sum(:balance)
        total_cash = family.accounts.sum { |a| calculate_cash_balance(a) }
        cash_pct = total_balance.zero? ? 0 : (total_cash / total_balance) * 100
        guardrail.check(cash_pct)
      else
        { passed: true, message: nil }
      end
    end

    # Builds an action hash (not yet persisted)
    def build_action(action_type:, title:, description:, severity:, metadata: {})
      {
        action_type: action_type,
        title: title,
        description: description,
        priority: score_priority(action_type, severity),
        metadata: metadata,
        severity: severity
      }
    end

    # Persists actions, avoiding duplicates
    def persist_actions(actions)
      return if actions.empty?

      # Get existing active action keys to avoid duplicates
      existing_keys = family.top_actions.active.pluck(:title).to_set

      actions.each do |action_data|
        # Skip if similar action already exists
        next if existing_keys.include?(action_data[:title])

        family.top_actions.create!(
          action_type: action_data[:action_type],
          title: action_data[:title],
          description: action_data[:description],
          priority: action_data[:priority],
          metadata: action_data[:metadata]
        )

        existing_keys.add(action_data[:title])
      end
    end
  end
end

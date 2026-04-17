class RegimeDetectionJob < ApplicationJob
  queue_as :scheduled

  REGIMES = %w[normal caution crisis].freeze

  DRAWDOWN_THRESHOLDS = {
    caution: 0.10,  # 10% drawdown
    crisis: 0.20    # 20% drawdown
  }.freeze

  VOLATILITY_THRESHOLDS = {
    caution: 0.15,  # 15% annualized volatility
    crisis: 0.25    # 25% annualized volatility
  }.freeze

  # Detects market regime based on portfolio drawdown and volatility
  # Runs on a schedule to update the regime mode for recommendations
  #
  # @param lookback_days [Integer] Number of days to analyze for regime detection (default: 90)
  def perform(lookback_days: 90)
    Rails.logger.info("RegimeDetectionJob: Starting regime detection with #{lookback_days} day lookback")

    families_with_holdings = Family.joins(:holdings).distinct

    families_with_holdings.find_each do |family|
      detect_regime_for_family(family, lookback_days)
    end

    Rails.logger.info("RegimeDetectionJob: Completed regime detection for #{families_with_holdings.count} family(s)")
  rescue StandardError => e
    Rails.logger.error("RegimeDetectionJob: Failed: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    raise
  end

  private

    def detect_regime_for_family(family, lookback_days)
      return unless family.holdings.any?

      portfolio_data = fetch_portfolio_data(family, lookback_days)
      return if portfolio_data.empty?

      drawdown = calculate_max_drawdown(portfolio_data)
      volatility = calculate_volatility(portfolio_data)

      regime = determine_regime(drawdown, volatility)

      store_regime_for_family(family, regime, drawdown, volatility, portfolio_data)

      Rails.logger.info("RegimeDetectionJob: Family #{family.id} regime: #{regime} (drawdown: #{(drawdown * 100).round(2)}%, volatility: #{(volatility * 100).round(2)}%)")
    rescue StandardError => e
      Rails.logger.error("RegimeDetectionJob: Failed to detect regime for family #{family.id}: #{e.message}")
    end

    def fetch_portfolio_data(family, lookback_days)
      start_date = lookback_days.days.ago.to_date

      family.holdings
        .where("date >= ?", start_date)
        .group(:date)
        .sum(:amount)
        .sort_by { |date, _| date }
        .map { |date, amount| { date: date, value: amount.to_f } }
    end

    def calculate_max_drawdown(portfolio_data)
      return 0.0 if portfolio_data.size < 2

      peak = portfolio_data.first[:value]
      max_drawdown = 0.0

      portfolio_data.each do |data|
        value = data[:value]
        peak = value if value > peak

        next if peak.zero?

        drawdown = (peak - value) / peak
        max_drawdown = drawdown if drawdown > max_drawdown
      end

      max_drawdown
    end

    def calculate_volatility(portfolio_data)
      return 0.0 if portfolio_data.size < 2

      values = portfolio_data.map { |d| d[:value] }
      returns = []

      (1...values.size).each do |i|
        next if values[i - 1].zero?

        daily_return = (values[i] - values[i - 1]) / values[i - 1]
        returns << daily_return
      end

      return 0.0 if returns.size < 2

      mean = returns.sum / returns.size
      variance = returns.sum { |r| (r - mean) ** 2 } / (returns.size - 1)
      std_dev = Math.sqrt(variance)

      annualized_volatility = std_dev * Math.sqrt(252)

      annualized_volatility
    end

    def determine_regime(drawdown, volatility)
      crisis_score = 0
      caution_score = 0

      if drawdown >= DRAWDOWN_THRESHOLDS[:crisis]
        crisis_score += 2
      elsif drawdown >= DRAWDOWN_THRESHOLDS[:caution]
        caution_score += 1
      end

      if volatility >= VOLATILITY_THRESHOLDS[:crisis]
        crisis_score += 2
      elsif volatility >= VOLATILITY_THRESHOLDS[:caution]
        caution_score += 1
      end

      if crisis_score >= 2
        "crisis"
      elsif crisis_score >= 1 || caution_score >= 2
        "caution"
      else
        "normal"
      end
    end

    def store_regime_for_family(family, regime, drawdown, volatility, portfolio_data)
      regime_data = {
        regime: regime,
        drawdown: drawdown.round(4),
        volatility: volatility.round(4),
        calculated_at: Time.current.iso8601,
        lookback_days: portfolio_data.size,
        thresholds: {
          drawdown_caution: DRAWDOWN_THRESHOLDS[:caution],
          drawdown_crisis: DRAWDOWN_THRESHOLDS[:crisis],
          volatility_caution: VOLATILITY_THRESHOLDS[:caution],
          volatility_crisis: VOLATILITY_THRESHOLDS[:crisis]
        }
      }

      existing_action = family.top_actions.active.by_type("manual_review")
        .find_by("metadata->>'regime_detection' = ?", "true")

      if existing_action && regime != "normal"
        existing_action.update!(
          title: "Market Regime: #{regime.titleize}",
          description: build_regime_description(regime, drawdown, volatility),
          priority: regime_priority(regime),
          metadata: existing_action.metadata.merge(regime_detection: true, regime_data: regime_data)
        )
      elsif regime != "normal"
        family.top_actions.create!(
          action_type: "manual_review",
          title: "Market Regime: #{regime.titleize}",
          description: build_regime_description(regime, drawdown, volatility),
          priority: regime_priority(regime),
          metadata: { regime_detection: true, regime_data: regime_data }
        )
      elsif existing_action && regime == "normal"
        existing_action.dismiss! if existing_action.title.include?("Market Regime")
      end

      Rails.cache.write("family:#{family.id}:market_regime", regime_data, expires_in: 24.hours)
    end

    def build_regime_description(regime, drawdown, volatility)
      case regime
      when "crisis"
        "Market regime indicates crisis conditions. Maximum drawdown: #{(drawdown * 100).round(1)}%, " \
          "volatility: #{(volatility * 100).round(1)}%. Consider defensive positioning."
      when "caution"
        "Market regime indicates caution conditions. Maximum drawdown: #{(drawdown * 100).round(1)}%, " \
          "volatility: #{(volatility * 100).round(1)}%. Monitor positions closely."
      else
        "Market regime is normal. Maximum drawdown: #{(drawdown * 100).round(1)}%, " \
          "volatility: #{(volatility * 100).round(1)}%."
      end
    end

    def regime_priority(regime)
      case regime
      when "crisis"
        9
      when "caution"
        6
      else
        3
      end
    end
end

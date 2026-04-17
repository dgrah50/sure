class RegimeDetector
  MARKET_PROXY_TICKER = "SPY".freeze
  BTC_TICKER_PATTERN = /BTC/i

  # Drawdown thresholds
  CRISIS_DRAWDOWN_90D = 0.20  # 20% drawdown over 90 days = crisis
  CRISIS_BTC_DRAWDOWN = 0.30  # 30% BTC drawdown = crisis
  CAUTION_DRAWDOWN_30D = 0.10 # 10% drawdown over 30 days = caution

  # Volatility spike threshold (relative to historical average)
  VOLATILITY_SPIKE_MULTIPLIER = 2.0
  VOLATILITY_LOOKBACK_DAYS = 30

  attr_reader :family

  def initialize(family)
    @family = family
  end

  # Detects the current market regime mode
  # @return [Hash] with :mode, :indicators, :confidence, :last_updated
  def detect
    indicators = calculate_indicators
    mode = determine_mode(indicators)
    confidence = calculate_confidence(indicators)

    {
      mode: mode,
      indicators: indicators,
      confidence: confidence,
      last_updated: Time.current
    }
  end

  private

    def calculate_indicators
      {
        market_drawdown_30d: calculate_market_drawdown(30),
        market_drawdown_90d: calculate_market_drawdown(90),
        volatility_spike: detect_volatility_spike,
        btc_drawdown: calculate_btc_drawdown
      }.compact
    end

    def determine_mode(indicators)
      return :unknown if insufficient_data?(indicators)

      market_90d = indicators[:market_drawdown_90d] || 0
      btc_drawdown = indicators[:btc_drawdown] || 0
      volatility = indicators[:volatility_spike]

      # Crisis: Severe drawdowns
      return :crisis if market_90d > CRISIS_DRAWDOWN_90D
      return :crisis if btc_drawdown > CRISIS_BTC_DRAWDOWN

      # Caution: Moderate drawdowns or volatility spike
      market_30d = indicators[:market_drawdown_30d] || 0
      return :caution if market_30d > CAUTION_DRAWDOWN_30D
      return :caution if volatility && volatility[:spike_detected]

      # Normal: All indicators within acceptable ranges
      :normal
    end

    def calculate_confidence(indicators)
      return :low if insufficient_data?(indicators)

      data_points = 0
      data_points += 1 if indicators[:market_drawdown_30d].present?
      data_points += 1 if indicators[:market_drawdown_90d].present?
      data_points += 1 if indicators[:volatility_spike].present?
      data_points += 1 if indicators[:btc_drawdown].present?

      case data_points
      when 4 then :high
      when 2..3 then :medium
      else :low
      end
    end

    def insufficient_data?(indicators)
      indicators[:market_drawdown_30d].nil? && indicators[:market_drawdown_90d].nil?
    end

    def calculate_market_drawdown(days)
      market_security = find_market_proxy
      return nil unless market_security

      current_price = fetch_current_price(market_security)
      return nil unless current_price

      historical_price = fetch_historical_price(market_security, days.days.ago.to_date)
      return nil unless historical_price && historical_price > 0

      (historical_price - current_price) / historical_price.to_f
    end

    def calculate_btc_drawdown
      btc_security = find_btc_security
      return nil unless btc_security

      current_price = fetch_current_price(btc_security)
      return nil unless current_price

      # Use 90-day lookback for BTC crisis detection
      historical_price = fetch_historical_price(btc_security, 90.days.ago.to_date)
      return nil unless historical_price && historical_price > 0

      (historical_price - current_price) / historical_price.to_f
    end

    def detect_volatility_spike
      market_security = find_market_proxy
      return nil unless market_security

      recent_volatility = calculate_volatility(market_security, 10)
      historical_volatility = calculate_volatility(market_security, VOLATILITY_LOOKBACK_DAYS, offset: 10)

      return nil if recent_volatility.nil? || historical_volatility.nil? || historical_volatility.zero?

      spike_ratio = recent_volatility / historical_volatility

      {
        spike_detected: spike_ratio > VOLATILITY_SPIKE_MULTIPLIER,
        recent_volatility: recent_volatility,
        historical_volatility: historical_volatility,
        spike_ratio: spike_ratio
      }
    end

    def calculate_volatility(security, days, offset: 0)
      end_date = Date.current - offset.days
      start_date = end_date - days.days

      prices = fetch_price_series(security, start_date, end_date)
      return nil if prices.size < 2

      # Calculate daily returns
      returns = []
      prices.each_cons(2) do |prev, curr|
        next if prev[:price].zero?
        returns << (curr[:price] - prev[:price]) / prev[:price].to_f
      end

      return nil if returns.empty?

      # Standard deviation of returns (volatility)
      mean = returns.sum / returns.size.to_f
      variance = returns.sum { |r| (r - mean)**2 } / returns.size.to_f
      Math.sqrt(variance)
    end

    def find_market_proxy
      @market_proxy ||= Security.find_by(ticker: MARKET_PROXY_TICKER)
    end

    def find_btc_security
      # Look for BTC securities that the family actually holds
      family.holdings
            .joins(:security)
            .where("securities.ticker ~ ?", BTC_TICKER_PATTERN)
            .distinct
            .pluck(:security_id)
            .first
            &.then { |id| Security.find_by(id: id) }
    end

    def fetch_current_price(security)
      # Try to get the most recent price
      price_record = security.prices.where(date: ..Date.current).order(date: :desc).first
      return nil unless price_record

      price_record.price
    end

    def fetch_historical_price(security, date)
      # Get price on or closest to the target date
      price_record = security.prices.where(date: ..date).order(date: :desc).first
      return nil unless price_record

      price_record.price
    end

    def fetch_price_series(security, start_date, end_date)
      security.prices
              .where(date: start_date..end_date)
              .order(date: :asc)
              .pluck(:date, :price)
              .map { |date, price| { date: date, price: price } }
    end
end

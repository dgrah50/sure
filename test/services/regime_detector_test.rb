require "test_helper"

class RegimeDetectorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @detector = RegimeDetector.new(@family)
  end

  test "detect returns hash with required keys" do
    result = @detector.detect

    assert result.key?(:mode)
    assert result.key?(:indicators)
    assert result.key?(:confidence)
    assert result.key?(:last_updated)
    assert_includes [:normal, :caution, :crisis, :unknown], result[:mode]
    assert_includes [:high, :medium, :low], result[:confidence]
  end

  test "detect returns unknown when no market proxy data available" do
    # Ensure no SPY security exists
    Security.where(ticker: "SPY").destroy_all

    result = @detector.detect

    assert_equal :unknown, result[:mode]
    assert_equal :low, result[:confidence]
    assert_nil result[:indicators][:market_drawdown_30d]
    assert_nil result[:indicators][:market_drawdown_90d]
  end

  test "detect returns normal when market is stable" do
    spy = create_spy_security
    create_stable_prices(spy)

    result = @detector.detect

    assert_equal :normal, result[:mode]
    assert result[:indicators][:market_drawdown_30d] < 0.05
    assert result[:indicators][:market_drawdown_90d] < 0.05
  end

  test "detect returns caution when 30d drawdown exceeds 10%" do
    spy = create_spy_security
    create_drawdown_prices(spy, drawdown: 0.12, days: 30)

    result = @detector.detect

    assert_equal :caution, result[:mode]
    assert result[:indicators][:market_drawdown_30d] > 0.10
  end

  test "detect returns crisis when 90d drawdown exceeds 20%" do
    spy = create_spy_security
    create_drawdown_prices(spy, drawdown: 0.25, days: 90)

    result = @detector.detect

    assert_equal :crisis, result[:mode]
    assert result[:indicators][:market_drawdown_90d] > 0.20
  end

  test "detect returns crisis when BTC drawdown exceeds 30%" do
    spy = create_spy_security
    btc = create_btc_security
    create_stable_prices(spy)
    create_btc_drawdown_prices(btc, drawdown: 0.35)
    create_btc_holding(btc)

    result = @detector.detect

    assert_equal :crisis, result[:mode]
    assert result[:indicators][:btc_drawdown] > 0.30
  end

  test "detect returns caution when volatility spike detected" do
    spy = create_spy_security
    create_volatile_prices(spy)

    result = @detector.detect

    assert_equal :caution, result[:mode]
    assert result[:indicators][:volatility_spike][:spike_detected]
  end

  test "indicators include all expected keys" do
    spy = create_spy_security
    btc = create_btc_security
    create_stable_prices(spy)
    create_btc_drawdown_prices(btc, drawdown: 0.10)
    create_btc_holding(btc)

    result = @detector.detect

    assert result[:indicators].key?(:market_drawdown_30d)
    assert result[:indicators].key?(:market_drawdown_90d)
    assert result[:indicators].key?(:volatility_spike)
    assert result[:indicators].key?(:btc_drawdown)
  end

  test "volatility spike detection returns detailed information" do
    spy = create_spy_security
    create_volatile_prices(spy)

    result = @detector.detect

    volatility = result[:indicators][:volatility_spike]
    assert volatility.key?(:spike_detected)
    assert volatility.key?(:recent_volatility)
    assert volatility.key?(:historical_volatility)
    assert volatility.key?(:spike_ratio)
    assert volatility[:recent_volatility] > 0
    assert volatility[:historical_volatility] > 0
  end

  test "confidence is high when all indicators available" do
    spy = create_spy_security
    btc = create_btc_security
    create_stable_prices(spy)
    create_btc_drawdown_prices(btc, drawdown: 0.05)
    create_btc_holding(btc)
    # Add enough prices for volatility calculation
    create_volatile_prices(spy)

    result = @detector.detect

    assert_equal :high, result[:confidence]
  end

  test "confidence is low when only market data available" do
    spy = create_spy_security
    create_stable_prices(spy, days: 5) # Not enough for volatility

    result = @detector.detect

    assert_equal :low, result[:confidence]
  end

  test "btc_drawdown is nil when family has no BTC holdings" do
    spy = create_spy_security
    create_stable_prices(spy)

    result = @detector.detect

    assert_nil result[:indicators][:btc_drawdown]
  end

  test "last_updated is current timestamp" do
    freeze_time do
      result = @detector.detect
      assert_equal Time.current, result[:last_updated]
    end
  end

  private

    def create_spy_security
      Security.create!(
        ticker: "SPY",
        name: "SPDR S&P 500 ETF",
        kind: "standard"
      )
    end

    def create_btc_security
      Security.create!(
        ticker: "BTCUSD",
        name: "Bitcoin USD",
        kind: "standard",
        exchange_operating_mic: "BINANCE"
      )
    end

    def create_stable_prices(security, base_price: 400.0, days: 100)
      (days + 1).downto(0) do |i|
        date = i.days.ago.to_date
        # Small random fluctuation around base price
        price = base_price * (1 + rand(-0.02..0.02))
        create_price(security, date, price)
      end
    end

    def create_drawdown_prices(security, drawdown:, days:)
      base_price = 400.0
      end_price = base_price * (1 - drawdown)

      # Create historical prices at base level
      100.downto(days) do |i|
        date = i.days.ago.to_date
        create_price(security, date, base_price * (1 + rand(-0.01..0.01)))
      end

      # Create drawdown over the specified period
      days.downto(0) do |i|
        date = i.days.ago.to_date
        progress = (days - i) / days.to_f
        price = base_price - (progress * (base_price - end_price))
        create_price(security, date, price * (1 + rand(-0.005..0.005)))
      end
    end

    def create_btc_drawdown_prices(security, drawdown:)
      base_price = 50000.0
      end_price = base_price * (1 - drawdown)

      100.downto(90) do |i|
        date = i.days.ago.to_date
        create_price(security, date, base_price)
      end

      90.downto(0) do |i|
        date = i.days.ago.to_date
        progress = (90 - i) / 90.0
        price = base_price - (progress * (base_price - end_price))
        create_price(security, date, price)
      end
    end

    def create_volatile_prices(security)
      base_price = 400.0

      # Create 40 days of historical prices
      40.downto(0) do |i|
        date = i.days.ago.to_date

        if i <= 10
          # Recent period: high volatility (large swings)
          volatility = 0.05
        else
          # Historical period: low volatility
          volatility = 0.01
        end

        price = base_price * (1 + rand(-volatility..volatility))
        create_price(security, date, price)
      end
    end

    def create_price(security, date, price)
      Security::Price.find_or_create_by!(
        security: security,
        date: date,
        currency: "USD"
      ) do |p|
        p.price = price.round(2)
        p.confidence = :live
      end
    end

    def create_btc_holding(security)
      account = @family.accounts.first
      return unless account

      Holding.find_or_create_by!(
        account: account,
        security: security,
        date: Date.current
      ) do |h|
        h.qty = 1.0
        h.price = 50000.0
        h.amount = 50000.0
        h.currency = "USD"
      end
    end
end

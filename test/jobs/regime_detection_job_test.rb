require "test_helper"

class RegimeDetectionJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @account = @family.accounts.create!(
      name: "Test Brokerage",
      balance: 10000,
      currency: "USD",
      accountable: Investment.new
    )

    @security = Security.create!(
      ticker: "TEST",
      name: "Test Security",
      exchange_code: "XNAS"
    )

    # Create holdings with known values for predictable calculations
    create_holding(100.days.ago.to_date, 10000)
    create_holding(90.days.ago.to_date, 10500)  # Peak
    create_holding(80.days.ago.to_date, 9000)   # 14.3% drawdown
    create_holding(70.days.ago.to_date, 8500)   # 19% drawdown
    create_holding(60.days.ago.to_date, 8000)   # 23.8% drawdown (crisis)
    create_holding(30.days.ago.to_date, 9500)
    create_holding(Date.current, 9800)
  end

  test "job calculates drawdown correctly" do
    RegimeDetectionJob.perform_now(lookback_days: 100)

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert_not_nil regime_data
    assert regime_data[:drawdown] > 0
  end

  test "job calculates volatility correctly" do
    RegimeDetectionJob.perform_now(lookback_days: 100)

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert_not_nil regime_data
    assert regime_data[:volatility] >= 0
  end

  test "job creates regime top action for crisis conditions" do
    # Create holdings that trigger crisis regime (>20% drawdown, >25% volatility)
    Holding.where(account: @family.accounts).destroy_all

    # Create volatile declining pattern
    values = [10000, 9500, 9000, 8000, 7500, 7000, 7200, 6800, 6500, 6200]
    values.each_with_index do |value, i|
      create_holding((10 - i).days.ago.to_date, value)
    end

    assert_difference -> { TopAction.count }, 1 do
      RegimeDetectionJob.perform_now(lookback_days: 15)
    end

    top_action = TopAction.last
    assert_equal "manual_review", top_action.action_type
    assert top_action.title.include?("Crisis")
    assert top_action.metadata["regime_detection"]
  end

  test "job creates regime top action for caution conditions" do
    # Create holdings with moderate drawdown (10-20%)
    Holding.where(account: @family.accounts).destroy_all

    values = [10000, 9800, 9500, 9200, 8800, 8500, 8300, 8600, 8800, 9000]
    values.each_with_index do |value, i|
      create_holding((10 - i).days.ago.to_date, value)
    end

    assert_difference -> { TopAction.count }, 1 do
      RegimeDetectionJob.perform_now(lookback_days: 15)
    end

    top_action = TopAction.last
    assert_equal "manual_review", top_action.action_type
    assert top_action.title.include?("Caution")
  end

  test "job does not create top action for normal regime" do
    # Create stable holdings (minimal drawdown)
    Holding.where(account: @family.accounts).destroy_all

    values = [10000, 10100, 10050, 10200, 10150, 10300, 10250, 10400]
    values.each_with_index do |value, i|
      create_holding((8 - i).days.ago.to_date, value)
    end

    assert_no_difference -> { TopAction.count } do
      RegimeDetectionJob.perform_now(lookback_days: 10)
    end

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert_equal "normal", regime_data[:regime]
  end

  test "job updates existing regime action instead of creating duplicate" do
    # Create existing regime action
    existing_action = @family.top_actions.create!(
      action_type: "manual_review",
      title: "Market Regime: Caution",
      description: "Old regime data",
      priority: 6,
      metadata: { regime_detection: true, regime_data: { regime: "caution" } }
    )

    # Create holdings that trigger caution
    Holding.where(account: @family.accounts).destroy_all
    values = [10000, 9800, 9500, 9200, 8800, 8500]
    values.each_with_index do |value, i|
      create_holding((6 - i).days.ago.to_date, value)
    end

    assert_no_difference -> { TopAction.count } do
      RegimeDetectionJob.perform_now(lookback_days: 10)
    end

    existing_action.reload
    assert existing_action.metadata["regime_data"][:drawdown].present?
  end

  test "job dismisses regime action when returning to normal" do
    # Create existing crisis regime action
    existing_action = @family.top_actions.create!(
      action_type: "manual_review",
      title: "Market Regime: Crisis",
      description: "Crisis conditions",
      priority: 9,
      metadata: { regime_detection: true, regime_data: { regime: "crisis" } }
    )

    # Create stable holdings
    Holding.where(account: @family.accounts).destroy_all
    values = [10000, 10100, 10050, 10200]
    values.each_with_index do |value, i|
      create_holding((4 - i).days.ago.to_date, value)
    end

    RegimeDetectionJob.perform_now(lookback_days: 7)

    existing_action.reload
    assert existing_action.dismissed?
  end

  test "job handles families without holdings" do
    family_without_holdings = families(:empty)

    assert_nothing_raised do
      RegimeDetectionJob.perform_now(lookback_days: 90)
    end
  end

  test "job calculates max drawdown with peak tracking" do
    # Create specific pattern: rise, then fall below peak, then new peak, then bigger fall
    Holding.where(account: @family.accounts).destroy_all

    create_holding(5.days.ago.to_date, 10000)
    create_holding(4.days.ago.to_date, 11000)  # Peak 1
    create_holding(3.days.ago.to_date, 10500)  # 4.5% drawdown
    create_holding(2.days.ago.to_date, 11500)  # Peak 2 (new peak)
    create_holding(1.day.ago.to_date, 9200)    # 20% drawdown from peak 2
    create_holding(Date.current, 9500)

    RegimeDetectionJob.perform_now(lookback_days: 10)

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert_in_delta 0.20, regime_data[:drawdown], 0.02  # ~20% drawdown
  end

  test "job calculates annualized volatility" do
    # Create volatile pattern
    Holding.where(account: @family.accounts).destroy_all

    values = [10000, 10500, 9800, 11000, 9500, 10800, 9200, 11200]
    values.each_with_index do |value, i|
      create_holding((8 - i).days.ago.to_date, value)
    end

    RegimeDetectionJob.perform_now(lookback_days: 10)

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert regime_data[:volatility] > 0
  end

  test "job handles zero values in portfolio data" do
    Holding.where(account: @family.accounts).destroy_all

    create_holding(2.days.ago.to_date, 10000)
    create_holding(1.day.ago.to_date, 0)  # Edge case: zero value
    create_holding(Date.current, 5000)

    assert_nothing_raised do
      RegimeDetectionJob.perform_now(lookback_days: 7)
    end
  end

  test "job handles single day of holdings" do
    Holding.where(account: @family.accounts).destroy_all
    create_holding(Date.current, 10000)

    assert_nothing_raised do
      RegimeDetectionJob.perform_now(lookback_days: 7)
    end

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert_equal 0.0, regime_data[:drawdown]
    assert_equal 0.0, regime_data[:volatility]
  end

  test "job stores regime data in cache" do
    RegimeDetectionJob.perform_now(lookback_days: 100)

    regime_data = Rails.cache.read("family:#{@family.id}:market_regime")
    assert_not_nil regime_data
    assert_includes %w[normal caution crisis], regime_data[:regime]
    assert regime_data[:drawdown].present?
    assert regime_data[:volatility].present?
    assert regime_data[:calculated_at].present?
    assert regime_data[:thresholds].present?
  end

  test "job sets correct priority for crisis regime" do
    Holding.where(account: @family.accounts).destroy_all

    # Trigger crisis
    values = [10000, 9500, 9000, 8000, 7500, 7000, 6500, 6000]
    values.each_with_index do |value, i|
      create_holding((8 - i).days.ago.to_date, value)
    end

    assert_difference -> { TopAction.count }, 1 do
      RegimeDetectionJob.perform_now(lookback_days: 10)
    end

    top_action = TopAction.last
    assert_equal 9, top_action.priority
  end

  test "job sets correct priority for caution regime" do
    Holding.where(account: @family.accounts).destroy_all

    # Trigger caution
    values = [10000, 9800, 9500, 9200, 8800]
    values.each_with_index do |value, i|
      create_holding((5 - i).days.ago.to_date, value)
    end

    assert_difference -> { TopAction.count }, 1 do
      RegimeDetectionJob.perform_now(lookback_days: 7)
    end

    top_action = TopAction.last
    assert_equal 6, top_action.priority
  end

  test "job includes description with drawdown and volatility" do
    Holding.where(account: @family.accounts).destroy_all

    values = [10000, 9500, 9000, 8500]
    values.each_with_index do |value, i|
      create_holding((4 - i).days.ago.to_date, value)
    end

    assert_difference -> { TopAction.count }, 1 do
      RegimeDetectionJob.perform_now(lookback_days: 7)
    end

    top_action = TopAction.last
    assert_includes top_action.description, "%"
  end

  private

    def create_holding(date, amount)
      Holding.create!(
        account: @account,
        security: @security,
        date: date,
        qty: 100,
        price: amount / 100.0,
        amount: amount,
        currency: "USD"
      )
    end
end

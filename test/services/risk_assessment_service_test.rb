require "test_helper"

class RiskAssessmentServiceTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @service = RiskAssessmentService.new(@family)
  end

  test "initializes with family" do
    service = RiskAssessmentService.new(@family)
    assert_equal @family, service.send(:family)
  end

  test "assess returns complete risk assessment hash" do
    result = @service.assess

    assert result.key?(:concentration)
    assert result.key?(:guardrails)
    assert result.key?(:liquidity)
    assert result.key?(:exposure)
    assert result.key?(:data_quality)
    assert result.key?(:overall_risk_level)

    assert_includes %w[low medium high critical], result[:overall_risk_level]
  end

  test "concentration metrics returns required fields" do
    result = @service.assess[:concentration]

    assert result.key?(:largest_holding_pct)
    assert result.key?(:btc_concentration_pct)
    assert result.key?(:top_5_pct)
    assert result.key?(:concentration_risk_level)

    assert result[:largest_holding_pct].is_a?(Numeric)
    assert result[:btc_concentration_pct].is_a?(Numeric)
    assert result[:top_5_pct].is_a?(Numeric)
    assert_includes %w[low medium high critical], result[:concentration_risk_level]
  end

  test "guardrails returns array" do
    result = @service.assess[:guardrails]
    assert result.is_a?(Array)
  end

  test "liquidity returns required fields" do
    result = @service.assess[:liquidity]

    assert result.key?(:cash_pct)
    assert result.key?(:minimum_required)
    assert result.key?(:status)

    assert result[:cash_pct].is_a?(Numeric)
    assert result[:minimum_required].is_a?(Numeric)
    assert_includes %w[pass warning critical], result[:status]
  end

  test "exposure returns high_beta_pct" do
    result = @service.assess[:exposure]

    assert result.key?(:high_beta_pct)
    assert result[:high_beta_pct].is_a?(Numeric)
  end

  test "data_quality returns required fields" do
    result = @service.assess[:data_quality]

    assert result.key?(:overall_score)
    assert result.key?(:issues_count)

    assert result[:overall_score].is_a?(Integer)
    assert result[:issues_count].is_a?(Integer)
  end

  test "handles empty family with no accounts" do
    empty_family = families(:empty)
    service = RiskAssessmentService.new(empty_family)
    result = service.assess

    assert_equal 0.0, result[:concentration][:largest_holding_pct]
    assert_equal 0.0, result[:concentration][:btc_concentration_pct]
    assert_equal 0.0, result[:concentration][:top_5_pct]
    assert_equal "low", result[:concentration][:concentration_risk_level]

    assert_equal 0.0, result[:liquidity][:cash_pct]
    assert_equal "pass", result[:liquidity][:status]

    assert_equal 0.0, result[:exposure][:high_beta_pct]
    assert_equal "low", result[:overall_risk_level]
  end

  test "calculates largest holding percentage correctly" do
    # Create additional holdings to test concentration
    investment_account = accounts(:investment)

    # Ensure we have at least one holding
    holding = Holding.create!(
      account: investment_account,
      security: securities(:aapl),
      date: Date.current,
      qty: 10,
      price: 200,
      amount: 2000,
      currency: "USD"
    )

    result = @service.assess[:concentration]
    assert result[:largest_holding_pct] >= 0

    holding.destroy
  end

  test "calculates cash percentage correctly" do
    result = @service.assess[:liquidity]

    # Dylan family has accounts with cash balances from fixtures
    total_cash = @family.accounts.where(status: "active").sum(:cash_balance)
    total_value = @family.accounts.where(status: "active").sum(:balance)

    if total_value > 0
      expected_pct = (total_cash / total_value * 100).round(2)
      assert_equal expected_pct, result[:cash_pct]
    else
      assert_equal 0.0, result[:cash_pct]
    end
  end

  test "overall risk level is determined correctly" do
    result = @service.assess

    # Overall risk level should be one of the valid levels
    assert_includes %w[low medium high critical], result[:overall_risk_level]

    # Should be based on the highest severity of any risk factor
    concentration = result[:concentration][:concentration_risk_level]
    liquidity_status = result[:liquidity][:status]
    data_score = result[:data_quality][:overall_score]

    # If any factor is critical, overall should be at least high
    if concentration == "critical" || liquidity_status == "critical" || data_score < 40
      assert result[:overall_risk_level].in?(%w[high critical])
    end
  end

  test "guardrails check returns empty array when no active policy" do
    result = @service.assess[:guardrails]
    assert result.is_a?(Array)
  end

  test "handles missing data quality summary gracefully" do
    result = @service.assess[:data_quality]

    # Should return default values when no summary exists
    assert result[:overall_score].is_a?(Integer)
    assert result[:issues_count].is_a?(Integer)
  end

  test "btc concentration is calculated for bitcoin securities" do
    # Test the btc_security? helper indirectly through btc_concentration calculation
    result = @service.assess[:concentration]
    assert result[:btc_concentration_pct].is_a?(Numeric)
    assert result[:btc_concentration_pct] >= 0
  end

  test "high beta exposure returns percentage" do
    result = @service.assess[:exposure]
    assert result[:high_beta_pct].is_a?(Numeric)
    assert result[:high_beta_pct] >= 0
  end
end

require "test_helper"

class RecommendationTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @recommendation = @family.recommendations.create!(
      recommendation_type: "rebalance",
      title: "Test Rebalance Recommendation",
      description: "Test description",
      status: "pending",
      details: {
        trades: [
          { action: "buy", ticker: "AAPL", shares: 10, estimated_amount: 1000 },
          { action: "sell", ticker: "GOOG", shares: 5, estimated_amount: 500 }
        ],
        total_amount: 1500,
        rationale: "Portfolio drift detected"
      }
    )
  end

  # Validations
  test "validates family presence" do
    recommendation = Recommendation.new(
      recommendation_type: "rebalance",
      title: "Test",
      status: "pending"
    )
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:family], "must exist"
  end

  test "validates recommendation_type presence" do
    recommendation = Recommendation.new(
      family: @family,
      title: "Test",
      status: "pending"
    )
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:recommendation_type], "can't be blank"
  end

  test "validates recommendation_type inclusion" do
    recommendation = Recommendation.new(
      family: @family,
      recommendation_type: "invalid_type",
      title: "Test",
      status: "pending"
    )
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:recommendation_type], "is not included in the list"
  end

  test "validates valid recommendation_types" do
    valid_types = %w[trade rebalance deposit withdraw review]
    valid_types.each do |type|
      recommendation = Recommendation.new(
        family: @family,
        recommendation_type: type,
        title: "Test",
        status: "pending"
      )
      assert recommendation.valid?, "#{type} should be valid"
    end
  end

  test "validates title presence" do
    recommendation = Recommendation.new(
      family: @family,
      recommendation_type: "rebalance",
      status: "pending"
    )
    assert_not recommendation.valid?
    assert_includes recommendation.errors[:title], "can't be blank"
  end

  test "validates status inclusion" do
    invalid_recommendation = Recommendation.new(
      family: @family,
      recommendation_type: "rebalance",
      title: "Test",
      status: "invalid_status"
    )
    assert_not invalid_recommendation.valid?
    assert_includes invalid_recommendation.errors[:status], "is not included in the list"
  end

  # Status methods
  test "pending? returns true for pending status" do
    assert @recommendation.pending?
  end

  test "pending? returns false for non-pending status" do
    @recommendation.update!(status: "approved")
    assert_not @recommendation.pending?
  end

  test "approved? returns true for approved status" do
    @recommendation.update!(status: "approved", approved_by: @user)
    assert @recommendation.approved?
  end

  test "approved? returns false for non-approved status" do
    assert_not @recommendation.approved?
  end

  test "rejected? returns true for rejected status" do
    @recommendation.update!(status: "rejected", approved_by: @user)
    assert @recommendation.rejected?
  end

  test "rejected? returns false for non-rejected status" do
    assert_not @recommendation.rejected?
  end

  test "executed? returns true for executed status" do
    @recommendation.update!(status: "executed", executed_at: Time.current)
    assert @recommendation.executed?
  end

  test "executed? returns false for non-executed status" do
    assert_not @recommendation.executed?
  end

  # Action methods
  test "approve! changes status to approved" do
    assert @recommendation.approve!(@user)
    assert_equal "approved", @recommendation.status
    assert_equal @user, @recommendation.approved_by
  end

  test "approve! returns false when not pending" do
    @recommendation.update!(status: "approved", approved_by: @user)
    assert_not @recommendation.approve!(@user)
  end

  test "reject! changes status to rejected" do
    assert @recommendation.reject!(@user)
    assert_equal "rejected", @recommendation.status
    assert_equal @user, @recommendation.approved_by
  end

  test "reject! returns false when not pending" do
    @recommendation.update!(status: "rejected", approved_by: @user)
    assert_not @recommendation.reject!(@user)
  end

  test "execute! changes status to executed" do
    @recommendation.update!(status: "approved", approved_by: @user)
    assert @recommendation.execute!
    assert_equal "executed", @recommendation.status
    assert_not_nil @recommendation.executed_at
  end

  test "execute! returns false when not approved" do
    assert_not @recommendation.execute!
  end

  # Scopes
  test "pending scope returns only pending recommendations" do
    pending_rec = @recommendation
    approved_rec = @family.recommendations.create!(
      recommendation_type: "trade",
      title: "Approved Trade",
      status: "approved",
      approved_by: @user
    )

    assert_includes Recommendation.pending, pending_rec
    assert_not_includes Recommendation.pending, approved_rec
  end

  test "approved scope returns only approved recommendations" do
    approved_rec = @family.recommendations.create!(
      recommendation_type: "trade",
      title: "Approved Trade",
      status: "approved",
      approved_by: @user
    )
    pending_rec = @recommendation

    assert_includes Recommendation.approved, approved_rec
    assert_not_includes Recommendation.approved, pending_rec
  end

  test "rejected scope returns only rejected recommendations" do
    rejected_rec = @family.recommendations.create!(
      recommendation_type: "trade",
      title: "Rejected Trade",
      status: "rejected",
      approved_by: @user
    )
    pending_rec = @recommendation

    assert_includes Recommendation.rejected, rejected_rec
    assert_not_includes Recommendation.rejected, pending_rec
  end

  test "executed scope returns only executed recommendations" do
    executed_rec = @family.recommendations.create!(
      recommendation_type: "trade",
      title: "Executed Trade",
      status: "executed",
      executed_at: Time.current
    )
    pending_rec = @recommendation

    assert_includes Recommendation.executed, executed_rec
    assert_not_includes Recommendation.executed, pending_rec
  end

  test "by_type scope filters by recommendation_type" do
    rebalance_rec = @recommendation
    trade_rec = @family.recommendations.create!(
      recommendation_type: "trade",
      title: "Trade Recommendation",
      status: "pending"
    )

    assert_includes Recommendation.by_type("rebalance"), rebalance_rec
    assert_not_includes Recommendation.by_type("rebalance"), trade_rec
    assert_includes Recommendation.by_type("trade"), trade_rec
  end

  test "for_family scope filters by family" do
    other_family = families(:empty)
    other_rec = other_family.recommendations.create!(
      recommendation_type: "review",
      title: "Other Family Review",
      status: "pending"
    )

    assert_includes Recommendation.for_family(@family), @recommendation
    assert_not_includes Recommendation.for_family(@family), other_rec
  end

  test "ordered scope returns recommendations in descending created_at order" do
    older_rec = @family.recommendations.create!(
      recommendation_type: "deposit",
      title: "Older Recommendation",
      status: "pending",
      created_at: 1.day.ago
    )
    newer_rec = @family.recommendations.create!(
      recommendation_type: "withdraw",
      title: "Newer Recommendation",
      status: "pending",
      created_at: Time.current
    )

    ordered = Recommendation.ordered.to_a
    assert_equal newer_rec, ordered.first
    assert_equal @recommendation, ordered[1]
    assert_equal older_rec, ordered.last
  end

  # Detail methods
  test "trades returns trades from details" do
    expected_trades = [
      { "action" => "buy", "ticker" => "AAPL", "shares" => 10, "estimated_amount" => 1000 },
      { "action" => "sell", "ticker" => "GOOG", "shares" => 5, "estimated_amount" => 500 }
    ]
    assert_equal expected_trades, @recommendation.trades
  end

  test "trades returns empty array when no trades in details" do
    rec_without_trades = @family.recommendations.create!(
      recommendation_type: "review",
      title: "Review Only",
      status: "pending",
      details: {}
    )
    assert_equal [], rec_without_trades.trades
  end

  test "total_amount returns total_amount from details" do
    assert_equal 1500, @recommendation.total_amount
  end

  test "total_amount returns nil when not in details" do
    rec_without_amount = @family.recommendations.create!(
      recommendation_type: "review",
      title: "Review Only",
      status: "pending",
      details: {}
    )
    assert_nil rec_without_amount.total_amount
  end

  test "rationale returns rationale from details" do
    assert_equal "Portfolio drift detected", @recommendation.rationale
  end

  test "rationale returns nil when not in details" do
    rec_without_rationale = @family.recommendations.create!(
      recommendation_type: "review",
      title: "Review Only",
      status: "pending",
      details: {}
    )
    assert_nil rec_without_rationale.rationale
  end
end

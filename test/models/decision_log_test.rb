require "test_helper"

class DecisionLogTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @recommendation = @family.recommendations.create!(
      recommendation_type: "rebalance",
      title: "Test Recommendation",
      status: "pending"
    )
    @decision_log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Approved based on analysis"
    )
  end

  # Validations
  test "validates family presence" do
    log = DecisionLog.new(
      actor: @user,
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test"
    )
    assert_not log.valid?
    assert_includes log.errors[:family], "must exist"
  end

  test "validates actor presence" do
    log = DecisionLog.new(
      family: @family,
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test"
    )
    assert_not log.valid?
    assert_includes log.errors[:actor], "must exist"
  end

  test "validates decision_type presence" do
    log = DecisionLog.new(
      family: @family,
      actor: @user,
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test"
    )
    assert_not log.valid?
    assert_includes log.errors[:decision_type], "can't be blank"
  end

  test "validates decision_type inclusion" do
    log = DecisionLog.new(
      family: @family,
      actor: @user,
      decision_type: "invalid_type",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test"
    )
    assert_not log.valid?
    assert_includes log.errors[:decision_type], "is not included in the list"
  end

  test "validates valid decision_types" do
    valid_types = %w[action_dismissed recommendation_approved recommendation_rejected manual_override]
    valid_types.each do |type|
      log = DecisionLog.new(
        family: @family,
        actor: @user,
        decision_type: type,
        reference_type: "Recommendation",
        reference_id: @recommendation.id,
        rationale: "Test"
      )
      assert log.valid?, "#{type} should be valid"
    end
  end

  test "validates reference_type presence" do
    log = DecisionLog.new(
      family: @family,
      actor: @user,
      decision_type: "recommendation_approved",
      reference_id: @recommendation.id,
      rationale: "Test"
    )
    assert_not log.valid?
    assert_includes log.errors[:reference_type], "can't be blank"
  end

  test "validates reference_id presence" do
    log = DecisionLog.new(
      family: @family,
      actor: @user,
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      rationale: "Test"
    )
    assert_not log.valid?
    assert_includes log.errors[:reference_id], "can't be blank"
  end

  test "validates rationale presence" do
    log = DecisionLog.new(
      family: @family,
      actor: @user,
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      reference_id: @recommendation.id
    )
    assert_not log.valid?
    assert_includes log.errors[:rationale], "can't be blank"
  end

  # Reference method
  test "reference returns the associated record" do
    assert_equal @recommendation, @decision_log.reference
  end

  test "reference returns nil when record not found" do
    log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "action_dismissed",
      reference_type: "Recommendation",
      reference_id: 99999,
      rationale: "Test"
    )
    assert_nil log.reference
  end

  test "reference works with TopAction" do
    top_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Test Action",
      priority: 5
    )
    log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "action_dismissed",
      reference_type: "TopAction",
      reference_id: top_action.id,
      rationale: "Test"
    )
    assert_equal top_action, log.reference
  end

  # Type methods
  test "action_dismissed? returns true for action_dismissed type" do
    log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "action_dismissed",
      reference_type: "TopAction",
      reference_id: @family.top_actions.create!(
        action_type: "rebalance_needed",
        title: "Test Action",
        priority: 5
      ).id,
      rationale: "Test"
    )
    assert log.action_dismissed?
  end

  test "action_dismissed? returns false for other types" do
    assert_not @decision_log.action_dismissed?
  end

  test "recommendation_approved? returns true for recommendation_approved type" do
    assert @decision_log.recommendation_approved?
  end

  test "recommendation_approved? returns false for other types" do
    log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "recommendation_rejected",
      reference_type: "Recommendation",
      reference_id: @family.recommendations.create!(
        recommendation_type: "trade",
        title: "Test",
        status: "pending"
      ).id,
      rationale: "Test"
    )
    assert_not log.recommendation_approved?
  end

  test "recommendation_rejected? returns true for recommendation_rejected type" do
    log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "recommendation_rejected",
      reference_type: "Recommendation",
      reference_id: @family.recommendations.create!(
        recommendation_type: "trade",
        title: "Test",
        status: "pending"
      ).id,
      rationale: "Test"
    )
    assert log.recommendation_rejected?
  end

  test "recommendation_rejected? returns false for other types" do
    assert_not @decision_log.recommendation_rejected?
  end

  test "manual_override? returns true for manual_override type" do
    log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "manual_override",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test"
    )
    assert log.manual_override?
  end

  test "manual_override? returns false for other types" do
    assert_not @decision_log.manual_override?
  end

  # Scopes
  test "for_family scope filters by family" do
    other_family = families(:empty)
    other_log = other_family.decision_logs.create!(
      actor: users(:empty),
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      reference_id: other_family.recommendations.create!(
        recommendation_type: "review",
        title: "Test",
        status: "pending"
      ).id,
      rationale: "Test"
    )

    assert_includes DecisionLog.for_family(@family), @decision_log
    assert_not_includes DecisionLog.for_family(@family), other_log
  end

  test "by_type scope filters by decision_type" do
    approved_log = @decision_log
    dismissed_log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "action_dismissed",
      reference_type: "TopAction",
      reference_id: @family.top_actions.create!(
        action_type: "rebalance_needed",
        title: "Test Action",
        priority: 5
      ).id,
      rationale: "Test"
    )

    assert_includes DecisionLog.by_type("recommendation_approved"), approved_log
    assert_not_includes DecisionLog.by_type("recommendation_approved"), dismissed_log
    assert_includes DecisionLog.by_type("action_dismissed"), dismissed_log
  end

  test "by_actor scope filters by actor" do
    other_user = users(:family_member)
    other_log = @family.decision_logs.create!(
      actor: other_user,
      decision_type: "recommendation_rejected",
      reference_type: "Recommendation",
      reference_id: @family.recommendations.create!(
        recommendation_type: "trade",
        title: "Test",
        status: "pending"
      ).id,
      rationale: "Test"
    )

    assert_includes DecisionLog.by_actor(@user), @decision_log
    assert_not_includes DecisionLog.by_actor(@user), other_log
  end

  test "for_reference scope filters by reference" do
    other_rec = @family.recommendations.create!(
      recommendation_type: "deposit",
      title: "Other Recommendation",
      status: "pending"
    )
    other_log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "recommendation_approved",
      reference_type: "Recommendation",
      reference_id: other_rec.id,
      rationale: "Test"
    )

    assert_includes DecisionLog.for_reference(@recommendation), @decision_log
    assert_not_includes DecisionLog.for_reference(@recommendation), other_log
    assert_includes DecisionLog.for_reference(other_rec), other_log
  end

  test "recent scope returns logs in descending created_at order" do
    older_log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "manual_override",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test",
      created_at: 1.day.ago
    )
    newer_log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "action_dismissed",
      reference_type: "TopAction",
      reference_id: @family.top_actions.create!(
        action_type: "data_quality",
        title: "Test",
        priority: 5
      ).id,
      rationale: "Test",
      created_at: Time.current
    )

    recent = DecisionLog.recent.to_a
    assert_equal newer_log, recent.first
    assert_equal @decision_log, recent[1]
    assert_equal older_log, recent.last
  end

  test "since scope returns logs created after given date" do
    old_log = @family.decision_logs.create!(
      actor: @user,
      decision_type: "manual_override",
      reference_type: "Recommendation",
      reference_id: @recommendation.id,
      rationale: "Test",
      created_at: 10.days.ago
    )
    recent_log = @decision_log # created_at is now

    since_5_days = DecisionLog.since(5.days.ago).to_a
    assert_includes since_5_days, recent_log
    assert_not_includes since_5_days, old_log

    since_15_days = DecisionLog.since(15.days.ago).to_a
    assert_includes since_15_days, recent_log
    assert_includes since_15_days, old_log
  end

  # Class method
  test "log_decision creates a decision log with correct attributes" do
    top_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Test Action",
      priority: 5
    )

    log = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "action_dismissed",
      reference: top_action,
      rationale: "User dismissed this action"
    )

    assert log.persisted?
    assert_equal @family, log.family
    assert_equal @user, log.actor
    assert_equal "action_dismissed", log.decision_type
    assert_equal "TopAction", log.reference_type
    assert_equal top_action.id, log.reference_id
    assert_equal "User dismissed this action", log.rationale
  end

  test "log_decision accepts metadata" do
    log = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "manual_override",
      reference: @recommendation,
      rationale: "Manual override applied",
      metadata: { reason: "emergency", approved_by: "admin" }
    )

    assert_equal({ "reason" => "emergency", "approved_by" => "admin" }, log.metadata)
  end
end

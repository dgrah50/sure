require "test_helper"

class DecisionLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @user = users(:family_admin)

    @recommendation = @family.recommendations.create!(
      recommendation_type: "rebalance",
      title: "Test Recommendation",
      status: "pending"
    )

    @top_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Test Action",
      priority: 5
    )

    @decision_log = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "recommendation_approved",
      reference: @recommendation,
      rationale: "Approved for rebalancing"
    )
  end

  # Index action
  test "index returns decision logs for family" do
    get decision_logs_url

    assert_response :success
    assert_match @decision_log.decision_type, response.body
    assert_match @decision_log.rationale, response.body
  end

  test "index scoping only shows family decision logs" do
    other_family = families(:empty)
    other_user = users(:empty)
    other_rec = other_family.recommendations.create!(
      recommendation_type: "review",
      title: "Other Recommendation",
      status: "pending"
    )
    other_log = DecisionLog.log_decision(
      family: other_family,
      actor: other_user,
      decision_type: "recommendation_rejected",
      reference: other_rec,
      rationale: "Other family rationale"
    )

    get decision_logs_url

    assert_response :success
    assert_match @decision_log.rationale, response.body
    assert_no_match other_log.rationale, response.body
  end

  test "index filters by decision_type" do
    dismissed_log = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "action_dismissed",
      reference: @top_action,
      rationale: "Action dismissed"
    )

    get decision_logs_url, params: { decision_type: "action_dismissed" }

    assert_response :success
    assert_match dismissed_log.rationale, response.body
    # Should not show the approved log
    assert_no_match @decision_log.rationale, response.body
  end

  test "index filters by invalid decision_type" do
    get decision_logs_url, params: { decision_type: "invalid_type" }

    assert_response :success
    # Should show all logs since invalid type is ignored
    assert_match @decision_log.rationale, response.body
  end

  test "index filters by since date" do
    old_log = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "manual_override",
      reference: @recommendation,
      rationale: "Old decision",
      created_at: 10.days.ago
    )

    get decision_logs_url, params: { since: 5.days.ago.to_date }

    assert_response :success
    # Should show recent log but not old one
    assert_match @decision_log.rationale, response.body
    assert_no_match old_log.rationale, response.body
  end

  test "index combines decision_type and since filters" do
    recent_dismissed = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "action_dismissed",
      reference: @top_action,
      rationale: "Recently dismissed"
    )

    old_dismissed = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "action_dismissed",
      reference: @family.top_actions.create!(action_type: "data_quality", title: "Old Action", priority: 3),
      rationale: "Old dismissed",
      created_at: 10.days.ago
    )

    get decision_logs_url, params: { decision_type: "action_dismissed", since: 5.days.ago.to_date }

    assert_response :success
    assert_match recent_dismissed.rationale, response.body
    assert_no_match old_dismissed.rationale, response.body
    assert_no_match @decision_log.rationale, response.body
  end

  test "index paginates results" do
    # Create additional logs to test pagination
    5.times do |i|
      rec = @family.recommendations.create!(
        recommendation_type: "trade",
        title: "Trade #{i}",
        status: "pending"
      )
      DecisionLog.log_decision(
        family: @family,
        actor: @user,
        decision_type: "recommendation_approved",
        reference: rec,
        rationale: "Approved #{i}"
      )
    end

    get decision_logs_url, params: { per_page: 3 }

    assert_response :success
  end

  # Show action
  test "show returns specific decision log" do
    get decision_log_url(@decision_log)

    assert_response :success
    assert_match @decision_log.decision_type, response.body
    assert_match @decision_log.rationale, response.body
    assert_match @user.name, response.body
  end

  test "show includes reference information" do
    get decision_log_url(@decision_log)

    assert_response :success
    assert_match @recommendation.title, response.body
    assert_match @recommendation.class.name, response.body
  end

  test "show scoping only shows family decision log" do
    other_family = families(:empty)
    other_user = users(:empty)
    other_rec = other_family.recommendations.create!(
      recommendation_type: "review",
      title: "Other Recommendation",
      status: "pending"
    )
    other_log = DecisionLog.log_decision(
      family: other_family,
      actor: other_user,
      decision_type: "recommendation_rejected",
      reference: other_rec,
      rationale: "Other family rationale"
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      get decision_log_url(other_log)
    end
  end

  test "show displays metadata when present" do
    log_with_metadata = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "manual_override",
      reference: @recommendation,
      rationale: "Manual override with metadata",
      metadata: { key1: "value1", key2: "value2" }
    )

    get decision_log_url(log_with_metadata)

    assert_response :success
    assert_match "key1", response.body
    assert_match "value1", response.body
  end
end

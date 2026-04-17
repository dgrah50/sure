require "test_helper"

class TopActionTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @top_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Portfolio Rebalance Needed",
      description: "Portfolio has drifted from target allocations",
      priority: 8
    )
  end

  # Validations
  test "validates family presence" do
    action = TopAction.new(
      action_type: "rebalance_needed",
      title: "Test Action",
      priority: 5
    )
    assert_not action.valid?
    assert_includes action.errors[:family], "must exist"
  end

  test "validates action_type presence" do
    action = TopAction.new(
      family: @family,
      title: "Test Action",
      priority: 5
    )
    assert_not action.valid?
    assert_includes action.errors[:action_type], "can't be blank"
  end

  test "validates action_type inclusion" do
    action = TopAction.new(
      family: @family,
      action_type: "invalid_type",
      title: "Test Action",
      priority: 5
    )
    assert_not action.valid?
    assert_includes action.errors[:action_type], "is not included in the list"
  end

  test "validates valid action_types" do
    valid_types = %w[rebalance_needed policy_drift data_quality cash_idle manual_review compliance_issue]
    valid_types.each do |type|
      action = TopAction.new(
        family: @family,
        action_type: type,
        title: "Test Action",
        priority: 5
      )
      assert action.valid?, "#{type} should be valid"
    end
  end

  test "validates title presence" do
    action = TopAction.new(
      family: @family,
      action_type: "rebalance_needed",
      priority: 5
    )
    assert_not action.valid?
    assert_includes action.errors[:title], "can't be blank"
  end

  test "validates priority is integer between 1 and 10" do
    action_low = TopAction.new(
      family: @family,
      action_type: "rebalance_needed",
      title: "Test",
      priority: 0
    )
    assert_not action_low.valid?
    assert_includes action_low.errors[:priority], "is not included in the list"

    action_high = TopAction.new(
      family: @family,
      action_type: "rebalance_needed",
      title: "Test",
      priority: 11
    )
    assert_not action_high.valid?
    assert_includes action_high.errors[:priority], "is not included in the list"
  end

  test "validates priority must be an integer" do
    action = TopAction.new(
      family: @family,
      action_type: "rebalance_needed",
      title: "Test",
      priority: 5.5
    )
    assert_not action.valid?
    assert_includes action.errors[:priority], "must be an integer"
  end

  # Action methods
  test "dismiss! sets dismissed_at timestamp" do
    assert @top_action.dismiss!
    assert_not_nil @top_action.dismissed_at
  end

  test "dismiss! returns false when already dismissed" do
    @top_action.dismiss!
    assert_not @top_action.dismiss!
  end

  test "dismiss! returns false when already completed" do
    @top_action.complete!
    assert_not @top_action.dismiss!
  end

  test "complete! sets completed_at timestamp" do
    assert @top_action.complete!
    assert_not_nil @top_action.completed_at
  end

  test "complete! returns false when already completed" do
    @top_action.complete!
    assert_not @top_action.complete!
  end

  test "complete! works when dismissed" do
    @top_action.dismiss!
    assert @top_action.complete!
    assert_not_nil @top_action.completed_at
  end

  # Status methods
  test "dismissed? returns true when dismissed_at is present" do
    @top_action.update!(dismissed_at: Time.current)
    assert @top_action.dismissed?
  end

  test "dismissed? returns false when dismissed_at is nil" do
    assert_not @top_action.dismissed?
  end

  test "completed? returns true when completed_at is present" do
    @top_action.update!(completed_at: Time.current)
    assert @top_action.completed?
  end

  test "completed? returns false when completed_at is nil" do
    assert_not @top_action.completed?
  end

  test "expired? returns false when completed" do
    @top_action.update!(completed_at: Time.current, created_at: 60.days.ago)
    assert_not @top_action.expired?
  end

  test "expired? returns true when older than 30 days and not completed" do
    @top_action.update!(created_at: 31.days.ago)
    assert @top_action.expired?
  end

  test "expired? returns false when less than 30 days old" do
    @top_action.update!(created_at: 29.days.ago)
    assert_not @top_action.expired?
  end

  test "expired? returns false when exactly 30 days old" do
    @top_action.update!(created_at: 30.days.ago)
    assert_not @top_action.expired?
  end

  # Scopes
  test "active scope returns only non-dismissed, non-completed actions" do
    active_action = @top_action
    dismissed_action = @family.top_actions.create!(
      action_type: "policy_drift",
      title: "Dismissed Action",
      priority: 5,
      dismissed_at: Time.current
    )
    completed_action = @family.top_actions.create!(
      action_type: "data_quality",
      title: "Completed Action",
      priority: 5,
      completed_at: Time.current
    )

    active_actions = TopAction.active.to_a
    assert_includes active_actions, active_action
    assert_not_includes active_actions, dismissed_action
    assert_not_includes active_actions, completed_action
  end

  test "dismissed scope returns only dismissed actions" do
    dismissed_action = @family.top_actions.create!(
      action_type: "policy_drift",
      title: "Dismissed Action",
      priority: 5,
      dismissed_at: Time.current
    )
    active_action = @top_action

    dismissed_actions = TopAction.dismissed.to_a
    assert_includes dismissed_actions, dismissed_action
    assert_not_includes dismissed_actions, active_action
  end

  test "completed scope returns only completed actions" do
    completed_action = @family.top_actions.create!(
      action_type: "data_quality",
      title: "Completed Action",
      priority: 5,
      completed_at: Time.current
    )
    active_action = @top_action

    completed_actions = TopAction.completed.to_a
    assert_includes completed_actions, completed_action
    assert_not_includes completed_actions, active_action
  end

  test "high_priority scope returns actions with priority >= 7" do
    high_priority_action = @top_action # priority 8
    medium_priority_action = @family.top_actions.create!(
      action_type: "cash_idle",
      title: "Medium Priority",
      priority: 6
    )
    low_priority_action = @family.top_actions.create!(
      action_type: "manual_review",
      title: "Low Priority",
      priority: 3
    )

    high_priority = TopAction.high_priority.to_a
    assert_includes high_priority, high_priority_action
    assert_not_includes high_priority, medium_priority_action
    assert_not_includes high_priority, low_priority_action
  end

  test "by_type scope filters by action_type" do
    rebalance_action = @top_action
    policy_action = @family.top_actions.create!(
      action_type: "policy_drift",
      title: "Policy Drift",
      priority: 5
    )

    assert_includes TopAction.by_type("rebalance_needed"), rebalance_action
    assert_not_includes TopAction.by_type("rebalance_needed"), policy_action
    assert_includes TopAction.by_type("policy_drift"), policy_action
  end

  test "for_family scope filters by family" do
    other_family = families(:empty)
    other_action = other_family.top_actions.create!(
      action_type: "compliance_issue",
      title: "Other Family Action",
      priority: 5
    )

    assert_includes TopAction.for_family(@family), @top_action
    assert_not_includes TopAction.for_family(@family), other_action
  end

  test "ordered scope returns actions sorted by priority desc, then created_at desc" do
    older_high = @family.top_actions.create!(
      action_type: "data_quality",
      title: "Older High Priority",
      priority: 9,
      created_at: 2.days.ago
    )
    newer_high = @family.top_actions.create!(
      action_type: "cash_idle",
      title: "Newer High Priority",
      priority: 9,
      created_at: 1.day.ago
    )
    low_priority = @family.top_actions.create!(
      action_type: "manual_review",
      title: "Low Priority",
      priority: 3,
      created_at: Time.current
    )

    ordered = TopAction.ordered.to_a
    assert_equal newer_high, ordered[0] # Higher priority, more recent
    assert_equal older_high, ordered[1] # Higher priority, older
    assert_equal @top_action, ordered[2] # Lower priority
    assert_equal low_priority, ordered[3] # Lowest priority
  end
end

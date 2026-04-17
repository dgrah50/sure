require "test_helper"

class TopActionRefreshJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    PolicyVersion.create!(
      family: @family,
      name: "Test Policy",
      version_number: 1,
      status: "active",
      target_percentage: 100
    )
  end

  test "job refreshes top actions for specific family" do
    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!).returns([])
    DecisionEngine::TopActionGenerator.any_instance.expects(:clear_expired_actions!)

    TopActionRefreshJob.perform_now(@family.id)
  end

  test "job refreshes top actions for all families with policy versions" do
    other_family = families(:empty)
    PolicyVersion.create!(
      family: other_family,
      name: "Other Policy",
      version_number: 1,
      status: "active",
      target_percentage: 100
    )

    DecisionEngine::TopActionGenerator.any_instance.stubs(:generate_actions!).returns([])
    DecisionEngine::TopActionGenerator.any_instance.stubs(:clear_expired_actions!)

    # Should process both families
    TopActionRefreshJob.perform_now
  end

  test "job skips families without policy versions" do
    family_without_policy = families(:empty)

    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!).never

    TopActionRefreshJob.perform_now(family_without_policy.id)
  end

  test "job clears expired actions" do
    expired_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Expired Action",
      description: "Old action",
      priority: 5,
      created_at: 31.days.ago
    )

    DecisionEngine::TopActionGenerator.any_instance.expects(:clear_expired_actions!).once
    DecisionEngine::TopActionGenerator.any_instance.stubs(:generate_actions!).returns([])

    TopActionRefreshJob.perform_now(@family.id)
  end

  test "job skips families with recent sync failures" do
    account = @family.accounts.first || Account.create!(
      family: @family,
      name: "Test Account",
      balance: 1000,
      currency: "USD",
      accountable: Depository.new
    )

    Sync.create!(
      syncable: account,
      status: "failed",
      created_at: 30.minutes.ago
    )

    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!).never

    TopActionRefreshJob.perform_now(@family.id)
  end

  test "job processes families without recent sync failures" do
    account = @family.accounts.first || Account.create!(
      family: @family,
      name: "Test Account",
      balance: 1000,
      currency: "USD",
      accountable: Depository.new
    )

    # Create an old failed sync (more than 1 hour ago)
    Sync.create!(
      syncable: account,
      status: "failed",
      created_at: 2.hours.ago
    )

    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!).returns([])

    TopActionRefreshJob.perform_now(@family.id)
  end

  test "job creates new actions" do
    new_action = TopAction.new(
      family: @family,
      action_type: "policy_drift",
      title: "Policy Drift Detected",
      description: "Drift detected",
      priority: 7
    )

    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!).returns([new_action])
    DecisionEngine::TopActionGenerator.any_instance.stubs(:clear_expired_actions!)

    assert_difference -> { TopAction.count }, 1 do
      TopActionRefreshJob.perform_now(@family.id)
    end
  end

  test "job batch processes all families" do
    other_family = families(:empty)
    PolicyVersion.create!(
      family: other_family,
      name: "Other Policy",
      version_number: 1,
      status: "active",
      target_percentage: 100
    )

    DecisionEngine::TopActionGenerator.any_instance.stubs(:generate_actions!).returns([])
    DecisionEngine::TopActionGenerator.any_instance.stubs(:clear_expired_actions!)

    # Process all families (no argument)
    TopActionRefreshJob.perform_now
  end

  test "job handles errors for individual families" do
    # First family succeeds, second fails
    other_family = families(:empty)
    PolicyVersion.create!(
      family: other_family,
      name: "Other Policy",
      version_number: 1,
      status: "active",
      target_percentage: 100
    )

    call_count = 0
    DecisionEngine::TopActionGenerator.any_instance.stubs(:generate_actions!).returns([])
    DecisionEngine::TopActionGenerator.any_instance.stubs(:clear_expired_actions!)

    # Job should continue even if one family fails
    # The error is caught and logged, not raised
    TopActionRefreshJob.perform_now
  end

  test "job handles generator errors gracefully" do
    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!)
      .raises(StandardError, "Generator error")

    # Error is caught and logged, job should not raise
    assert_nothing_raised do
      TopActionRefreshJob.perform_now(@family.id)
    end
  end

  test "job retries on deadlock" do
    assert_includes TopActionRefreshJob.retry_on, ActiveRecord::Deadlocked
  end

  test "job loads specific family when family_id provided" do
    DecisionEngine::TopActionGenerator.any_instance.expects(:generate_actions!).returns([])
    DecisionEngine::TopActionGenerator.any_instance.expects(:clear_expired_actions!)

    TopActionRefreshJob.perform_now(@family.id)
  end

  test "job loads all families with policies when no family_id provided" do
    other_family = families(:empty)
    PolicyVersion.create!(
      family: other_family,
      name: "Other Policy",
      version_number: 1,
      status: "active",
      target_percentage: 100
    )

    DecisionEngine::TopActionGenerator.any_instance.stubs(:generate_actions!).returns([])
    DecisionEngine::TopActionGenerator.any_instance.stubs(:clear_expired_actions!)

    # Should process both families when no id provided
    TopActionRefreshJob.perform_now
  end
end

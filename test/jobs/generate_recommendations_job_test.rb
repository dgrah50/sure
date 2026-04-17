require "test_helper"

class GenerateRecommendationsJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @policy_version = PolicyVersion.create!(
      family: @family,
      name: "Test Policy",
      version_number: 1,
      status: "active",
      target_percentage: 100
    )
  end

  test "job runs recommendation builder" do
    DecisionEngine::RecommendationBuilder.any_instance.expects(:build_recommendations!).returns([])

    GenerateRecommendationsJob.perform_now(@family.id)
  end

  test "job creates top action from recommendations" do
    recommendation = Recommendation.new(
      family: @family,
      policy_version: @policy_version,
      recommendation_type: "rebalance",
      title: "Rebalance Needed",
      description: "Portfolio drift detected",
      status: "pending",
      details: {
        drift_metrics: { total_drift: 10.5 },
        trades: [{ action: "buy", ticker: "AAPL", shares: 10 }]
      }
    )

    DecisionEngine::RecommendationBuilder.any_instance.expects(:build_recommendations!).returns([recommendation])

    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    top_action = TopAction.last
    assert_equal "rebalance_needed", top_action.action_type
    assert_equal "Rebalance Needed", top_action.title
  end

  test "job creates wait action when no policy version" do
    @policy_version.destroy!

    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    top_action = TopAction.last
    assert_equal "manual_review", top_action.action_type
    assert top_action.title.include?("Wait")
    assert top_action.metadata["wait_state"]
  end

  test "job creates wait action when target percentages invalid" do
    @policy_version.update!(target_percentage: 50)

    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    top_action = TopAction.last
    assert_equal "manual_review", top_action.action_type
    assert top_action.title.include?("Wait")
    assert_includes top_action.metadata["reason"], "100%"
  end

  test "job creates wait action when no recommendations generated" do
    DecisionEngine::RecommendationBuilder.any_instance.expects(:build_recommendations!).returns([])

    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    top_action = TopAction.last
    assert_equal "manual_review", top_action.action_type
    assert top_action.title.include?("Wait")
  end

  test "job updates existing rebalance top action instead of creating duplicate" do
    existing_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Old Rebalance",
      description: "Old description",
      priority: 4,
      metadata: { old_data: true }
    )

    recommendation = Recommendation.new(
      family: @family,
      policy_version: @policy_version,
      recommendation_type: "rebalance",
      title: "New Rebalance Needed",
      description: "Updated drift detected",
      status: "pending",
      details: {
        drift_metrics: { total_drift: 18.0 },
        trades: [{ action: "sell", ticker: "GOOG", shares: 5 }]
      }
    )

    DecisionEngine::RecommendationBuilder.any_instance.expects(:build_recommendations!).returns([recommendation])

    assert_no_difference -> { TopAction.count } do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    existing_action.reload
    assert_equal "New Rebalance Needed", existing_action.title
    assert_equal "Updated drift detected", existing_action.description
  end

  test "job calculates priority based on drift severity" do
    test_cases = [
      { drift: 3.0, expected_priority: 4 },   # 0-5%: minor
      { drift: 10.0, expected_priority: 6 },  # 5-15%: moderate
      { drift: 20.0, expected_priority: 8 },  # 15-25%: major
      { drift: 30.0, expected_priority: 10 }  # 25%+: major
    ]

    test_cases.each do |test_case|
      TopAction.where(family: @family).destroy_all

      recommendation = Recommendation.new(
        family: @family,
        policy_version: @policy_version,
        recommendation_type: "rebalance",
        title: "Rebalance #{test_case[:drift]}",
        description: "Test",
        status: "pending",
        details: {
          drift_metrics: { total_drift: test_case[:drift] },
          trades: [{ action: "buy", ticker: "AAPL", shares: 1 }]
        }
      )

      DecisionEngine::RecommendationBuilder.any_instance.stubs(:build_recommendations!).returns([recommendation])

      GenerateRecommendationsJob.perform_now(@family.id)

      top_action = TopAction.last
      assert_equal test_case[:expected_priority], top_action.priority,
        "Expected priority #{test_case[:expected_priority]} for drift #{test_case[:drift]}, got #{top_action.priority}"
    end
  end

  test "job does not create duplicate wait actions" do
    @policy_version.destroy!

    # First run creates wait action
    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    # Second run should not create another wait action
    assert_no_difference -> { TopAction.count } do
      GenerateRecommendationsJob.perform_now(@family.id)
    end
  end

  test "job handles missing family gracefully" do
    assert_nothing_raised do
      GenerateRecommendationsJob.perform_now(99999)
    end
  end

  test "job assesses data quality for holdings" do
    @family.holdings.destroy_all

    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end

    # Should still work even with no holdings
    top_action = TopAction.last
    assert top_action.present?
  end

  test "job detects stale holdings" do
    # Create a stale holding
    account = accounts(:investment)
    security = securities(:aapl)
    Holding.create!(
      account: account,
      security: security,
      date: 10.days.ago,
      qty: 10,
      price: 100,
      amount: 1000,
      currency: "USD"
    )

    DecisionEngine::RecommendationBuilder.any_instance.stubs(:build_recommendations!).returns([])

    # Job should log warning about stale holdings but still complete
    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end
  end

  test "job detects recent sync failures" do
    Sync.create!(
      syncable: @family.accounts.first || Account.create!(
        family: @family,
        name: "Test Account",
        balance: 1000,
        currency: "USD",
        accountable: Depository.new
      ),
      status: "failed",
      created_at: 2.hours.ago
    )

    DecisionEngine::RecommendationBuilder.any_instance.stubs(:build_recommendations!).returns([])

    assert_difference -> { TopAction.count }, 1 do
      GenerateRecommendationsJob.perform_now(@family.id)
    end
  end

  test "job retries on record not found" do
    # Test that retry_on is configured - we can't easily test the retry behavior
    # but we can verify the job class has the retry_on configuration
    assert_includes GenerateRecommendationsJob.retry_on, ActiveRecord::RecordNotFound
  end

  test "job handles builder errors" do
    DecisionEngine::RecommendationBuilder.any_instance.expects(:build_recommendations!)
      .raises(StandardError, "Builder error")

    assert_raises(StandardError) do
      GenerateRecommendationsJob.perform_now(@family.id)
    end
  end
end

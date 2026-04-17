require "test_helper"

class RecommendationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @recommendation = @family.recommendations.create!(
      recommendation_type: "rebalance",
      title: "Portfolio Rebalance",
      description: "Rebalance portfolio to target allocations",
      status: "pending"
    )
  end

  # Index action
  test "index returns timeline with grouped recommendations" do
    # Create recommendations in different time periods
    today_rec = @family.recommendations.create!(
      recommendation_type: "trade",
      title: "Today's Trade",
      status: "pending",
      created_at: Time.current
    )
    this_week_rec = @family.recommendations.create!(
      recommendation_type: "deposit",
      title: "This Week Deposit",
      status: "pending",
      created_at: 2.days.ago
    )
    this_month_rec = @family.recommendations.create!(
      recommendation_type: "withdraw",
      title: "This Month Withdrawal",
      status: "pending",
      created_at: 10.days.ago
    )
    completed_rec = @family.recommendations.create!(
      recommendation_type: "review",
      title: "Completed Review",
      status: "approved",
      approved_by: @user,
      created_at: 5.days.ago
    )

    get recommendations_url

    assert_response :success
    assert_match today_rec.title, response.body
    assert_match this_week_rec.title, response.body
    assert_match this_month_rec.title, response.body
    assert_match completed_rec.title, response.body
  end

  test "index scoping only shows family recommendations" do
    other_family = families(:empty)
    other_rec = other_family.recommendations.create!(
      recommendation_type: "review",
      title: "Other Family Recommendation",
      status: "pending"
    )

    get recommendations_url

    assert_response :success
    assert_match @recommendation.title, response.body
    assert_no_match other_rec.title, response.body
  end

  # Show action
  test "show returns recommendation with decision logs" do
    decision_log = DecisionLog.log_decision(
      family: @family,
      actor: @user,
      decision_type: "recommendation_approved",
      reference: @recommendation,
      rationale: "Test approval"
    )

    get recommendation_url(@recommendation)

    assert_response :success
    assert_match @recommendation.title, response.body
    assert_match decision_log.decision_type, response.body
  end

  test "show scoping only shows family recommendation" do
    other_family = families(:empty)
    other_rec = other_family.recommendations.create!(
      recommendation_type: "review",
      title: "Other Family Recommendation",
      status: "pending"
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      get recommendation_url(other_rec)
    end
  end

  # Approve action
  test "approve changes status to approved and creates decision log" do
    assert_difference -> { DecisionLog.count }, 1 do
      post approve_recommendation_url(@recommendation), params: { rationale: "Approved for rebalancing" }
    end

    @recommendation.reload
    assert_equal "approved", @recommendation.status
    assert_equal @user, @recommendation.approved_by

    decision_log = DecisionLog.last
    assert_equal "recommendation_approved", decision_log.decision_type
    assert_equal "Approved for rebalancing", decision_log.rationale

    assert_redirected_to recommendation_path(@recommendation)
    assert_equal I18n.t("recommendations.approve.success"), flash[:notice]
  end

  test "approve uses default rationale when none provided" do
    post approve_recommendation_url(@recommendation)

    decision_log = DecisionLog.last
    assert_equal I18n.t("recommendations.approve.default_rationale"), decision_log.rationale
  end

  test "approve returns failure when not pending" do
    @recommendation.update!(status: "approved", approved_by: @user)

    post approve_recommendation_url(@recommendation)

    assert_redirected_to recommendation_path(@recommendation)
    assert_equal I18n.t("recommendations.approve.failure"), flash[:alert]
  end

  test "approve requires user permission" do
    sign_out
    sign_in users(:intro_user) # guest role user without family permissions

    post approve_recommendation_url(@recommendation)
    assert_redirected_to recommendations_path
  end

  test "approve with turbo_stream format" do
    post approve_recommendation_url(@recommendation), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
  end

  # Reject action
  test "reject changes status to rejected and creates decision log" do
    assert_difference -> { DecisionLog.count }, 1 do
      post reject_recommendation_url(@recommendation), params: { rationale: "Not suitable at this time" }
    end

    @recommendation.reload
    assert_equal "rejected", @recommendation.status
    assert_equal @user, @recommendation.approved_by

    decision_log = DecisionLog.last
    assert_equal "recommendation_rejected", decision_log.decision_type
    assert_equal "Not suitable at this time", decision_log.rationale

    assert_redirected_to recommendation_path(@recommendation)
    assert_equal I18n.t("recommendations.reject.success"), flash[:notice]
  end

  test "reject uses default rationale when none provided" do
    post reject_recommendation_url(@recommendation)

    decision_log = DecisionLog.last
    assert_equal I18n.t("recommendations.reject.default_rationale"), decision_log.rationale
  end

  test "reject returns failure when not pending" do
    @recommendation.update!(status: "rejected", approved_by: @user)

    post reject_recommendation_url(@recommendation)

    assert_redirected_to recommendation_path(@recommendation)
    assert_equal I18n.t("recommendations.reject.failure"), flash[:alert]
  end

  test "reject with turbo_stream format" do
    post reject_recommendation_url(@recommendation), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
  end

  # Dismiss action
  test "dismiss creates decision log for pending recommendations" do
    assert_difference -> { DecisionLog.count }, 1 do
      post dismiss_recommendation_url(@recommendation), params: { rationale: "Dismissed without action" }
    end

    decision_log = DecisionLog.last
    assert_equal "action_dismissed", decision_log.decision_type
    assert_equal "Dismissed without action", decision_log.rationale

    assert_redirected_to recommendations_path
    assert_equal I18n.t("recommendations.dismiss.success"), flash[:notice]
  end

  test "dismiss does not create decision log when rationale is missing for non-pending" do
    @recommendation.update!(status: "approved", approved_by: @user)

    assert_no_difference -> { DecisionLog.count } do
      post dismiss_recommendation_url(@recommendation)
    end

    assert_redirected_to recommendations_path
  end

  test "dismiss with turbo_stream format removes recommendation from list" do
    post dismiss_recommendation_url(@recommendation), params: { rationale: "Remove from list" }, as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
    assert_match(/remove/, response.body)
  end

  # Complete action
  test "complete changes status to executed" do
    @recommendation.update!(status: "approved", approved_by: @user)

    post complete_recommendation_url(@recommendation)

    @recommendation.reload
    assert_equal "executed", @recommendation.status
    assert_not_nil @recommendation.executed_at

    assert_redirected_to recommendation_path(@recommendation)
    assert_equal I18n.t("recommendations.complete.success"), flash[:notice]
  end

  test "complete returns failure when not approved" do
    post complete_recommendation_url(@recommendation)

    assert_redirected_to recommendation_path(@recommendation)
    assert_equal I18n.t("recommendations.complete.failure"), flash[:alert]
  end

  test "complete with turbo_stream format" do
    @recommendation.update!(status: "approved", approved_by: @user)

    post complete_recommendation_url(@recommendation), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
  end

  # Authorization
  test "approve requires user to be present" do
    Current.user = nil
    sign_out

    post approve_recommendation_url(@recommendation)
    assert_redirected_to recommendations_path
    assert_equal I18n.t("shared.require_user"), flash[:alert]
  end

  test "reject requires user to be present" do
    Current.user = nil
    sign_out

    post reject_recommendation_url(@recommendation)
    assert_redirected_to recommendations_path
  end

  test "actions with turbo_stream require user" do
    sign_out

    post approve_recommendation_url(@recommendation), as: :turbo_stream
    assert_response :forbidden
  end
end

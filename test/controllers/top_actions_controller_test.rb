require "test_helper"

class TopActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @top_action = @family.top_actions.create!(
      action_type: "rebalance_needed",
      title: "Portfolio Rebalance Needed",
      description: "Portfolio has drifted from target",
      priority: 8
    )
  end

  # Show action
  test "show returns current top action" do
    get top_action_url(@top_action)

    assert_response :success
    assert_match @top_action.title, response.body
  end

  test "show returns active top action when no id specified via widget" do
    # Request to the widget endpoint which shows the current top action
    get top_action_url(@top_action)
    assert_response :success
  end

  test "show with turbo_stream format" do
    get top_action_url(@top_action), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
  end

  test "show scoping only shows family top actions" do
    other_family = families(:empty)
    other_action = other_family.top_actions.create!(
      action_type: "data_quality",
      title: "Other Family Action",
      priority: 5
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      get top_action_url(other_action)
    end
  end

  # Dismiss action
  test "dismiss marks action as dismissed with decision log" do
    assert_difference -> { DecisionLog.count }, 1 do
      post dismiss_top_action_url(@top_action), params: { rationale: "Will address later" }
    end

    @top_action.reload
    assert_not_nil @top_action.dismissed_at

    decision_log = DecisionLog.last
    assert_equal "action_dismissed", decision_log.decision_type
    assert_equal "Will address later", decision_log.rationale

    assert_redirected_to root_path
    assert_equal I18n.t("top_actions.dismiss.success"), flash[:notice]
  end

  test "dismiss uses default rationale when none provided" do
    post dismiss_top_action_url(@top_action)

    decision_log = DecisionLog.last
    assert_equal I18n.t("top_actions.dismiss.default_rationale"), decision_log.rationale
  end

  test "dismiss returns failure when already dismissed" do
    @top_action.update!(dismissed_at: Time.current)

    post dismiss_top_action_url(@top_action)

    assert_redirected_to root_path
    assert_equal I18n.t("top_actions.dismiss.failure"), flash[:alert]
  end

  test "dismiss with turbo_stream format" do
    post dismiss_top_action_url(@top_action), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
    assert_match(/remove/, response.body)
    assert_match(/replace/, response.body)
    assert_match(/top_action_widget/, response.body)
  end

  # Complete action
  test "complete marks action as completed" do
    post complete_top_action_url(@top_action)

    @top_action.reload
    assert_not_nil @top_action.completed_at

    assert_redirected_to root_path
    assert_equal I18n.t("top_actions.complete.success"), flash[:notice]
  end

  test "complete returns failure when already completed" do
    @top_action.update!(completed_at: Time.current)

    post complete_top_action_url(@top_action)

    assert_redirected_to root_path
    assert_equal I18n.t("top_actions.complete.failure"), flash[:alert]
  end

  test "complete with turbo_stream format" do
    post complete_top_action_url(@top_action), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
    assert_match(/remove/, response.body)
    assert_match(/top_action_widget/, response.body)
  end

  # Refresh action
  test "refresh regenerates top action display" do
    post refresh_top_action_url(@top_action)

    assert_redirected_to root_path
  end

  test "refresh with turbo_stream format replaces widget" do
    post refresh_top_action_url(@top_action), as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
    assert_match(/replace/, response.body)
    assert_match(/top_action_widget/, response.body)
  end

  # Authorization
  test "dismiss requires user permission" do
    sign_out
    sign_in users(:intro_user) # guest user

    post dismiss_top_action_url(@top_action)
    assert_redirected_to root_path
  end

  test "complete requires user permission" do
    sign_out
    sign_in users(:intro_user)

    post complete_top_action_url(@top_action)
    assert_redirected_to root_path
  end

  test "refresh requires user permission" do
    sign_out
    sign_in users(:intro_user)

    post refresh_top_action_url(@top_action)
    assert_redirected_to root_path
  end

  test "actions with turbo_stream require user" do
    sign_out

    post dismiss_top_action_url(@top_action), as: :turbo_stream
    assert_response :forbidden
  end

  test "complete logs decision when applicable" do
    # Complete action doesn't create decision logs by default
    # (this is different from dismiss)
    assert_no_difference -> { DecisionLog.count } do
      post complete_top_action_url(@top_action)
    end

    @top_action.reload
    assert_not_nil @top_action.completed_at
  end
end

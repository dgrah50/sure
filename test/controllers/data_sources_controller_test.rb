require "test_helper"

class DataSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "show requires admin" do
    sign_in users(:family_member)
    get data_sources_path
    assert_redirected_to accounts_path
  end

  test "show displays data sources page" do
    get data_sources_path
    assert_response :success
    assert_select "h1", /Data Sources/
  end

  test "sync_all triggers sync for all provider items" do
    PlaidItem.any_instance.expects(:sync_later).once

    post sync_all_data_sources_path
    assert_redirected_to data_sources_path
    assert_match /sync/i, flash[:notice]
  end

  test "sync_all returns json response when requested" do
    post sync_all_data_sources_path, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert json.key?("synced")
    assert json.key?("breakdown")
  end

  test "disconnect marks provider as disconnected" do
    health_status = DataHealthStatus.create!(
      family: @user.family,
      provider_type: "PlaidItem",
      provider_id: plaid_items(:one).id,
      connection_state: :connected
    )

    post disconnect_data_source_path(health_status)
    assert_redirected_to data_sources_path

    health_status.reload
    assert health_status.disconnected?
  end
end

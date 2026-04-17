require "test_helper"

class DataHealthStatusTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @plaid_item = plaid_items(:one)
    @data_health_status = DataHealthStatus.create!(
      family: @family,
      provider_type: "PlaidItem",
      provider_id: @plaid_item.id,
      connection_state: :connected,
      price_freshness_score: 85,
      holdings_freshness_score: 90,
      overall_confidence: 87
    )
  end

  test "valid with required attributes" do
    assert @data_health_status.valid?
  end

  test "requires family" do
    @data_health_status.family = nil
    assert_not @data_health_status.valid?
    assert_includes @data_health_status.errors[:family_id], "can't be blank"
  end

  test "requires provider_type" do
    @data_health_status.provider_type = nil
    assert_not @data_health_status.valid?
    assert_includes @data_health_status.errors[:provider_type], "can't be blank"
  end

  test "requires provider_id" do
    @data_health_status.provider_id = nil
    assert_not @data_health_status.valid?
    assert_includes @data_health_status.errors[:provider_id], "can't be blank"
  end

  test "score attributes must be between 0 and 100" do
    @data_health_status.price_freshness_score = 150
    assert_not @data_health_status.valid?

    @data_health_status.price_freshness_score = -10
    assert_not @data_health_status.valid?
  end

  test "connection state enum works correctly" do
    assert @data_health_status.connected?
    assert_equal "connected", @data_health_status.connection_state

    @data_health_status.stale!
    assert @data_health_status.stale?

    @data_health_status.error!
    assert @data_health_status.error?

    @data_health_status.disconnected!
    assert @data_health_status.disconnected?
  end

  test "healthy? returns true when connected and scores are good" do
    assert @data_health_status.healthy?

    @data_health_status.price_freshness_score = 50
    assert_not @data_health_status.healthy?

    @data_health_status.price_freshness_score = 85
    @data_health_status.stale!
    assert_not @data_health_status.healthy?
  end

  test "status_badge_color returns appropriate colors" do
    assert_equal "success", @data_health_status.status_badge_color

    @data_health_status.price_freshness_score = 50
    assert_equal "warning", @data_health_status.status_badge_color

    @data_health_status.error!
    assert_equal "error", @data_health_status.status_badge_color

    @data_health_status.disconnected!
    assert_equal "secondary", @data_health_status.status_badge_color
  end

  test "sync_needed? returns true when never synced or stale" do
    @data_health_status.last_sync_at = nil
    assert @data_health_status.sync_needed?

    @data_health_status.last_sync_at = 25.hours.ago
    assert @data_health_status.sync_needed?

    @data_health_status.last_sync_at = 1.hour.ago
    assert_not @data_health_status.sync_needed?
  end

  test "provider returns the associated provider object" do
    provider = @data_health_status.provider
    assert_equal @plaid_item, provider
  end

  test "update_health_from_sync! updates status correctly on success" do
    @data_health_status.update!(connection_state: :error, error_message: "Old error")

    @data_health_status.update_health_from_sync!(sync_success: true)

    assert @data_health_status.connected?
    assert_nil @data_health_status.error_message
    assert @data_health_status.last_sync_at.present?
  end

  test "update_health_from_sync! updates status correctly on failure" do
    @data_health_status.update_health_from_sync!(
      sync_success: false,
      error_message: "Connection failed"
    )

    assert @data_health_status.error?
    assert_equal "Connection failed", @data_health_status.error_message
  end

  test "refresh_for_family! creates statuses for all provider items" do
    DataHealthStatus.where(family: @family).destroy_all

    statuses = DataHealthStatus.refresh_for_family!(@family)

    provider_types = statuses.pluck(:provider_type)
    assert_includes provider_types, "PlaidItem"
  end
end

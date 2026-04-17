require "test_helper"

class InstrumentMappingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @holding = holdings(:one)
  end

  test "index requires admin" do
    sign_in users(:family_member)
    get instrument_mappings_path
    assert_redirected_to accounts_path
  end

  test "index displays instrument mappings" do
    get instrument_mappings_path
    assert_response :success
    assert_select "h1", /Instrument Classification/
  end

  test "index filters by pending status" do
    get instrument_mappings_path(filter: "pending")
    assert_response :success
  end

  test "create excludes holding" do
    assert_difference "InstrumentMapping.count", 1 do
      post instrument_mappings_path, params: {
        holding_id: @holding.id,
        action_type: "exclude"
      }
    end

    mapping = InstrumentMapping.last
    assert mapping.excluded?
    assert_redirected_to instrument_mappings_path
  end

  test "update approves mapping" do
    mapping = InstrumentMapping.create!(
      holding: @holding,
      mapped_status: :pending,
      mapping_confidence: :low
    )

    patch instrument_mapping_path(mapping), params: {
      action_type: "approve",
      filter: "all"
    }

    mapping.reload
    assert mapping.approved?
    assert_redirected_to instrument_mappings_path(filter: "all")
  end

  test "update excludes mapping" do
    mapping = InstrumentMapping.create!(
      holding: @holding,
      mapped_status: :pending,
      mapping_confidence: :low
    )

    patch instrument_mapping_path(mapping), params: {
      action_type: "exclude",
      filter: "all"
    }

    mapping.reload
    assert mapping.excluded?
  end

  test "update resets mapping to pending" do
    mapping = InstrumentMapping.create!(
      holding: @holding,
      mapped_status: :approved,
      mapping_confidence: :high,
      user_approved_at: Time.current
    )

    patch instrument_mapping_path(mapping), params: {
      action_type: "reset",
      filter: "all"
    }

    mapping.reload
    assert mapping.pending?
    assert_nil mapping.user_approved_at
  end

  test "bulk_approve approves multiple holdings" do
    holding2 = holdings(:two)

    # Create a sleeve on the fly for testing
    policy_version = PolicyVersion.create!(
      family: @user.family,
      name: "Test Policy",
      version_number: 1,
      status: :active
    )
    sleeve = policy_version.sleeves.create!(name: "Test Sleeve", target_percentage: 100)

    assert_difference "InstrumentMapping.count", 2 do
      post bulk_approve_instrument_mappings_path, params: {
        holding_ids: [@holding.id, holding2.id],
        sleeve_id: sleeve.id,
        filter: "all"
      }
    end

    assert_redirected_to instrument_mappings_path(filter: "all")
    assert_match /approved/i, flash[:notice]
  end

  test "bulk_exclude excludes multiple holdings" do
    holding2 = holdings(:two)

    assert_difference "InstrumentMapping.count", 2 do
      post bulk_exclude_instrument_mappings_path, params: {
        holding_ids: [@holding.id, holding2.id],
        filter: "all"
      }
    end

    assert_redirected_to instrument_mappings_path(filter: "all")
    assert_match /excluded/i, flash[:notice]
  end
end

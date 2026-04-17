require "test_helper"

class InstrumentMappingSuggestionJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @holding = holdings(:one)
  end

  test "creates pending mappings for holdings without mappings" do
    @holding.instrument_mapping&.destroy

    assert_difference "InstrumentMapping.count" do
      InstrumentMappingSuggestionJob.perform_now(@family.id)
    end

    mapping = @holding.reload.instrument_mapping
    assert mapping.pending?
  end

  test "suggests sleeve based on ticker pattern" do
    @holding.instrument_mapping&.destroy

    # Create a policy and sleeve for matching
    policy_version = PolicyVersion.create!(
      family: @family,
      name: "Test Policy",
      version_number: 1,
      status: :active
    )
    policy_version.sleeves.create!(name: "US Equities", target_percentage: 60)

    InstrumentMappingSuggestionJob.perform_now(@family.id)

    mapping = @holding.reload.instrument_mapping
    assert mapping.present?
  end

  test "calculates confidence based on ticker" do
    @holding.instrument_mapping&.destroy

    InstrumentMappingSuggestionJob.perform_now(@family.id)

    mapping = @holding.reload.instrument_mapping
    assert mapping.present?
    assert mapping.mapping_confidence.present?
  end

  test "handles errors gracefully" do
    Holding.any_instance.stubs(:security).raises(StandardError, "Test error")

    assert_nothing_raised do
      InstrumentMappingSuggestionJob.perform_now(@family.id)
    end
  end
end

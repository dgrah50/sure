require "test_helper"

class DataHealthCheckJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "performs data health check for family" do
    assert_difference "DataHealthStatus.count", Family.count * 1 do
      DataHealthCheckJob.perform_now
    end
  end

  test "performs data health check for specific family" do
    assert_difference -> { DataHealthStatus.where(family: @family).count } do
      DataHealthCheckJob.perform_now(@family.id)
    end
  end

  test "creates data quality checks" do
    assert_difference "DataQualityCheck.count" do
      DataHealthCheckJob.perform_now(@family.id)
    end
  end

  test "refreshes data quality summary" do
    DataHealthCheckJob.perform_now(@family.id)

    summary = @family.data_quality_summary
    assert summary.present?
    assert summary.last_sync_at.present?
  end

  test "handles errors gracefully" do
    Family.any_instance.stubs(:data_health_statuses).raises(StandardError, "Test error")

    assert_nothing_raised do
      DataHealthCheckJob.perform_now(@family.id)
    end
  end
end

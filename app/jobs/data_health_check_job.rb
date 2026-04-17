class DataHealthCheckJob < ApplicationJob
  queue_as :default

  def perform(family_id = nil)
    families = family_id.present? ? Family.where(id: family_id) : Family.all

    families.find_each do |family|
      check_family_data_health(family)
    end
  end

  private

    def check_family_data_health(family)
      # Refresh data health statuses for all provider items
      DataHealthStatus.refresh_for_family!(family)

      # Refresh data quality summary
      DataQualitySummary.refresh!(family)

      # Run data quality checks
      run_quality_checks(family)

      # Log any connection errors
      log_connection_errors(family)
    rescue => e
      Rails.logger.error("DataHealthCheckJob failed for family #{family.id}: #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n"))
    end

    def run_quality_checks(family)
      # Check price freshness
      check_price_freshness(family)

      # Check FX rate freshness
      check_fx_freshness(family)

      # Check holdings quality
      check_holdings_quality(family)

      # Check account sync status
      check_account_syncs(family)
    end

    def check_price_freshness(family)
      return unless family.trades.any?

      freshness_checker = DataHealth::DataFreshness.new
      securities = family.trades.joins(:security).distinct.map(&:security)

      stale_count = securities.count { |s| !freshness_checker.fresh?(s) }

      status = if stale_count == 0
                 "pass"
               elsif stale_count < securities.count * 0.25
                 "warning"
               else
                 "fail"
               end

      DataQualityCheck.record_check!(
        family: family,
        check_type: "price_stale",
        status: status,
        details: {
          stale_count: stale_count,
          total_count: securities.count,
          message: "#{stale_count} of #{securities.count} securities have stale prices"
        }
      )
    end

    def check_fx_freshness(family)
      return unless family.requires_exchange_rates_data_provider?

      freshness_checker = DataHealth::DataFreshness.new

      stale_count = 0
      total_count = 0

      family.enabled_currency_codes.each do |currency_code|
        next if currency_code == family.primary_currency_code

        total_count += 1
        rate = ExchangeRate.find_by(from_currency: currency_code, to_currency: family.primary_currency_code)
        stale_count += 1 if rate.nil? || !freshness_checker.fresh?(rate)
      end

      return if total_count == 0

      status = if stale_count == 0
                 "pass"
               elsif stale_count < total_count * 0.25
                 "warning"
               else
                 "fail"
               end

      DataQualityCheck.record_check!(
        family: family,
        check_type: "fx_stale",
        status: status,
        details: {
          stale_count: stale_count,
          total_count: total_count,
          message: "#{stale_count} of #{total_count} exchange rates are stale"
        }
      )
    end

    def check_holdings_quality(family)
      return if family.holdings.none?

      scorer = DataHealth::ConfidenceScorer.new

      low_confidence_count = 0
      total_count = 0

      family.holdings.find_each do |holding|
        total_count += 1
        score = scorer.score_holding(holding)
        low_confidence_count += 1 if score < 50
      end

      status = if low_confidence_count == 0
                 "pass"
               elsif low_confidence_count < total_count * 0.25
                 "warning"
               else
                 "fail"
               end

      DataQualityCheck.record_check!(
        family: family,
        check_type: "holding_missing_basis",
        status: status,
        details: {
          low_confidence_count: low_confidence_count,
          total_count: total_count,
          message: "#{low_confidence_count} of #{total_count} holdings have low confidence scores"
        }
      )
    end

    def check_account_syncs(family)
      failed_syncs = family.syncs.where(status: "failed").where("created_at > ?", 24.hours.ago).count

      status = if failed_syncs == 0
                 "pass"
               elsif failed_syncs < 3
                 "warning"
               else
                 "fail"
               end

      DataQualityCheck.record_check!(
        family: family,
        check_type: "account_sync_failed",
        status: status,
        details: {
          failed_count: failed_syncs,
          message: "#{failed_syncs} syncs failed in the last 24 hours"
        }
      )
    end

    def log_connection_errors(family)
      family.data_health_statuses.error.each do |status|
        next if status.error_message.blank?

        Rails.logger.warn(
          "DataHealthCheckJob: Connection error for family #{family.id}, " \
          "provider #{status.provider_type}##{status.provider_id}: #{status.error_message}"
        )
      end
    end
end

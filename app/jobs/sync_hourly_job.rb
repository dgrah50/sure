class SyncHourlyJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  # Provider item classes that opt-in to hourly syncing
  HOURLY_SYNCABLES = [
    CoinstatsItem # https://coinstats.app/api-docs/rate-limits#plan-limits
  ].freeze

  def perform
    Rails.logger.info("Starting hourly sync")
    HOURLY_SYNCABLES.each do |syncable_class|
      sync_items(syncable_class)
    end
    Rails.logger.info("Completed hourly sync")
  end

  private

    def sync_items(syncable_class)
      syncable_class.active.find_each do |item|
        item.sync_later
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error("#{syncable_class.name} not found during sync: #{e.message}")
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("#{syncable_class.name} #{item.id} invalid during sync: #{e.message}")
      rescue => e
        Rails.logger.error("Failed to sync #{syncable_class.name} #{item.id}: #{e.class} - #{e.message}")
        Sentry.capture_exception(e, extra: { item_id: item.id, item_class: syncable_class.name, job: "SyncHourlyJob" })
        raise # Re-raise unexpected errors to trigger job retry
      end
    end
end

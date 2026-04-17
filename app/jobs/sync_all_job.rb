class SyncAllJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    Rails.logger.info("Starting sync for all families")
    Family.find_each do |family|
      family.sync_later
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("Family not found during sync: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Family #{family.id} invalid during sync: #{e.message}")
    rescue => e
      Rails.logger.error("Failed to sync family #{family.id}: #{e.class} - #{e.message}")
      Sentry.capture_exception(e, extra: { family_id: family.id, job: "SyncAllJob" })
      raise # Re-raise unexpected errors to trigger job retry
    end
    Rails.logger.info("Completed sync for all families")
  end
end

class Sync < ApplicationRecord
  # We run a cron that marks any syncs that have not been resolved in 24 hours as "stale"
  # Syncs often become stale when new code is deployed and the worker restarts
  STALE_AFTER = 24.hours

  # The max time that a sync will show in the UI (after 5 minutes)
  VISIBLE_FOR = 5.minutes

  # Health check threshold - if no successful sync in this period, considered unhealthy
  HEALTHY_SYNC_THRESHOLD = 24.hours

  include AASM

  Error = Class.new(StandardError)

  belongs_to :syncable, polymorphic: true

  belongs_to :parent, class_name: "Sync", optional: true
  has_many :children, class_name: "Sync", foreign_key: :parent_id, dependent: :destroy

  scope :ordered, -> { order(created_at: :desc) }
  scope :incomplete, -> { where("syncs.status IN (?)", %w[pending syncing]) }
  scope :visible, -> { incomplete.where("syncs.created_at > ?", VISIBLE_FOR.ago) }
  scope :successful, -> { where(status: :completed) }
  scope :recently_successful, -> { successful.where("completed_at > ?", HEALTHY_SYNC_THRESHOLD.ago) }

  after_commit :update_family_sync_timestamp
  after_commit :update_last_successful_sync, if: :completed?

  serialize :sync_stats, coder: JSON

  validate :window_valid

  # Sync state machine
  aasm column: :status, timestamps: true do
    state :pending, initial: true
    state :syncing
    state :completed
    state :failed
    state :stale

    after_all_transitions :handle_transition

    event :start, after_commit: :handle_start_transition do
      transitions from: :pending, to: :syncing
    end

    event :complete, after_commit: :handle_completion_transition do
      transitions from: :syncing, to: :completed
    end

    event :fail do
      transitions from: :syncing, to: :failed
    end

    # Marks a sync that never completed within the expected time window
    event :mark_stale do
      transitions from: %i[pending syncing], to: :stale
    end
  end

  class << self
    def clean
      incomplete.where("syncs.created_at < ?", STALE_AFTER.ago).find_each(&:mark_stale!)
    end
  end

  # Calculate the duration of the sync in seconds
  def duration_seconds
    return nil unless end_time.present? && start_time.present?

    (end_time - start_time).to_f
  end

<<<<<<< HEAD
  # Get the start time for duration calculation
=======
>>>>>>> finos
  def start_time
    syncing_at || pending_at
  end

<<<<<<< HEAD
  # Get the end time for duration calculation
=======
>>>>>>> finos
  def end_time
    completed_at || failed_at || (stale? ? updated_at : nil)
  end

  # Human-readable status message
  def humanized_status
    case status
    when "pending"
      status_text.presence || I18n.t("syncs.status.pending", default: "Waiting to start...")
    when "syncing"
      status_text.presence || I18n.t("syncs.status.syncing", default: "Syncing...")
    when "completed"
      I18n.t("syncs.status.completed", default: "Completed successfully")
    when "failed"
      I18n.t("syncs.status.failed", default: "Failed: %{error}", error: error)
    when "stale"
      I18n.t("syncs.status.stale", default: "Sync timed out")
    else
      status.to_s.humanize
    end
  end

  # Categorize errors into common types
  def error_category
    return nil if error.blank?

    error_lower = error.downcase

    if error_lower.match?(/authentication|unauthorized|401|403|forbidden|invalid.*token|expired.*token|access_token|credential/)
      :auth
    elsif error_lower.match?(/rate.*limit|too.*many.*requests|429|throttle|quota/)
      :rate_limit
    elsif error_lower.match?(/timeout|connection|network|refused|dns|unreachable|503|502|504|500.*error|server.*error/)
      :network
    elsif error_lower.match?(/item.*not.*found|account.*not.*found|404/)
      :not_found
    else
      :unknown
    end
  end

<<<<<<< HEAD
  # Check if this sync represents a healthy state
  # Returns true if the sync completed successfully and the syncable has synced recently
=======
>>>>>>> finos
  def healthy?
    return false unless completed?

    # Check if syncable has a recent successful sync
    if syncable.respond_to?(:last_successful_sync_at)
      syncable.last_successful_sync_at.present? && syncable.last_successful_sync_at >= HEALTHY_SYNC_THRESHOLD.ago
    else
      # Fallback: check this sync completed recently
      completed_at.present? && completed_at >= HEALTHY_SYNC_THRESHOLD.ago
    end
  end

<<<<<<< HEAD
  # Update the status text for user feedback
=======
>>>>>>> finos
  def update_status_text(text)
    update(status_text: text) if text.present?
  end

  def perform
    Rails.logger.tagged("Sync", id, syncable_type, syncable_id) do
      # This can happen on server restarts or if Sidekiq enqueues a duplicate job
      unless may_start?
        Rails.logger.warn("Sync #{id} is not in a valid state (#{aasm.from_state}) to start.  Skipping sync.")
        return
      end

      # Guard: syncable may have been deleted while job was queued
      unless syncable.present?
        Rails.logger.warn("Sync #{id} - syncable #{syncable_type}##{syncable_id} no longer exists. Marking as failed.")
        start! if may_start?
        fail!
        update(error: "Syncable record was deleted")
        return
      end

      # Guard: syncable may be scheduled for deletion
      if syncable.respond_to?(:scheduled_for_deletion?) && syncable.scheduled_for_deletion?
        Rails.logger.warn("Sync #{id} - syncable #{syncable_type}##{syncable_id} is scheduled for deletion. Skipping sync.")
        start! if may_start?
        fail!
        update(error: "Syncable record is scheduled for deletion")
        return
      end

      start!

      begin
        syncable.perform_sync(self)
      rescue => e
        fail!
        update(error: e.message)
        report_error(e)
      ensure
        finalize_if_all_children_finalized
      end
    end
  end

  # Finalizes the current sync AND parent (if it exists)
  def finalize_if_all_children_finalized
    Sync.transaction do
      lock!

      # If this is the "parent" and there are still children running, don't finalize.
      return unless all_children_finalized?

      if syncing?
        if has_failed_children?
          fail!
        else
          complete!
        end
      end

      # If we make it here, the sync is finalized.  Run post-sync, regardless of failure/success.
      perform_post_sync
    end

    # If this sync has a parent, try to finalize it so the child status propagates up the chain.
    parent&.finalize_if_all_children_finalized
  end

  # If a sync is pending, we can adjust the window if new syncs are created with a wider window.
  def expand_window_if_needed(new_window_start_date, new_window_end_date)
    return unless pending?
    return if self.window_start_date.nil? && self.window_end_date.nil? # already as wide as possible

    earliest_start_date = if self.window_start_date && new_window_start_date
      [ self.window_start_date, new_window_start_date ].min
    else
      nil
    end

    latest_end_date = if self.window_end_date && new_window_end_date
      [ self.window_end_date, new_window_end_date ].max
    else
      nil
    end

    update(
      window_start_date: earliest_start_date,
      window_end_date: latest_end_date
    )
  end

  private
    def log_status_change
      Rails.logger.info("changing from #{aasm.from_state} to #{aasm.to_state} (event: #{aasm.current_event})")
    end

    def has_failed_children?
      children.failed.any?
    end

    def all_children_finalized?
      children.incomplete.empty?
    end

    def perform_post_sync
      Rails.logger.info("Performing post-sync for #{syncable_type} (#{syncable.id})")
      syncable.perform_post_sync
      syncable.broadcast_sync_complete
    rescue => e
      Rails.logger.error("Error performing post-sync for #{syncable_type} (#{syncable.id}): #{e.message}")
      report_error(e)
    end

    def report_error(error)
      Sentry.capture_exception(error) do |scope|
        scope.set_tags(sync_id: id)
      end
    end

    def report_warnings
      todays_sync_count = syncable.syncs.where(created_at: Date.current.all_day).count

      if todays_sync_count > 10
        Sentry.capture_exception(
          Error.new("#{syncable_type} (#{syncable.id}) has exceeded 10 syncs today (count: #{todays_sync_count})"),
          level: :warning
        )
      end
    end

    def handle_start_transition
      report_warnings
    end

    def handle_transition
      log_status_change
    end

    def handle_completion_transition
      family.touch(:latest_sync_completed_at)
      update_last_successful_sync_timestamp
    end

    def update_last_successful_sync
      update_last_successful_sync_timestamp if completed?
    end

    def update_last_successful_sync_timestamp
      update_columns(last_successful_sync_at: Time.current)
      syncable.update_columns(last_successful_sync_at: Time.current) if syncable.respond_to?(:last_successful_sync_at)
    end

    def window_valid
      if window_start_date && window_end_date && window_start_date > window_end_date
        errors.add(:window_end_date, "must be greater than window_start_date")
      end
    end

    def update_family_sync_timestamp
      family.touch(:latest_sync_activity_at)
    end

    def family
      if syncable.is_a?(Family)
        syncable
      else
        syncable.family
      end
    end
end

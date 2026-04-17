module SyncHealthTrackable
  extend ActiveSupport::Concern

  included do
    enum :sync_health_status, { healthy: "healthy", warning: "warning", critical: "critical" }, prefix: true
  end

  HEALTHY_SYNC_THRESHOLD = 24.hours
  WARNING_SYNC_THRESHOLD = 3.days

  class_methods do
    def error_category(error_message)
      return :unknown if error_message.blank?

      msg_lower = error_message.downcase

      if msg_lower.match?(/authentication|unauthorized|401|403|forbidden|invalid.*token|expired|credential|login/)
        :auth
      elsif msg_lower.match?(/rate.*limit|too.*many.*requests|429|throttle|quota/)
        :rate_limit
      elsif msg_lower.match?(/institution.*down|institution.*error|institution.*not.*responding|bank.*down/)
        :institution_unavailable
      elsif msg_lower.match?(/timeout|connection.*error|network.*error|unreachable/)
        :network
      elsif msg_lower.match?(/account.*not.*found|item.*not.*found|404/)
        :not_found
      else
        :unknown
      end
    end
  end

  def calculate_sync_health_status
    sync_time = last_successful_sync_at || last_synced_at
    return :critical unless sync_time.present?

    hours_since_sync = (Time.current - sync_time) / 1.hour

    if hours_since_sync <= 24
      :healthy
    elsif hours_since_sync <= 72
      :warning
    else
      :critical
    end
  end

  def update_sync_health_status!
    new_status = calculate_sync_health_status
    update_column(:sync_health_status, new_status)
    new_status
  end

  def sync_healthy?
    sync_time = last_successful_sync_at || last_synced_at
    return false unless sync_time.present?

    sync_time >= HEALTHY_SYNC_THRESHOLD.ago
  end

  def sync_health_summary
    sync_time = last_successful_sync_at || last_synced_at
    return "Never synced" unless sync_time.present?

    hours_since = ((Time.current - sync_time) / 1.hour).round

    if sync_healthy?
      "Last synced #{hours_since} #{'hour'.pluralize(hours_since)} ago"
    elsif hours_since <= 72
      "Last synced #{hours_since} hours ago - may need attention"
    else
      days_since = (hours_since / 24).round
      "Last synced #{days_since} #{'day'.pluralize(days_since)} ago - connection may need update"
    end
  end

  def error_category(error_message = nil)
    self.class.error_category(error_message || syncs.failed.first&.error)
  end
end

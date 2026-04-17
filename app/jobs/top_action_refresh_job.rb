class TopActionRefreshJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Refreshes top actions for families
  # When family_id is provided, only refreshes that family
  # Otherwise refreshes all families that have policy versions
  #
  # @param family_id [Integer, nil] Optional family ID to scope the refresh
  def perform(family_id = nil)
    families = load_families(family_id)

    Rails.logger.info("TopActionRefreshJob: Refreshing top actions for #{families.count} family(s)")

    families.find_each do |family|
      refresh_family_actions(family)
    end

    Rails.logger.info("TopActionRefreshJob: Completed refresh")
  rescue StandardError => e
    Rails.logger.error("TopActionRefreshJob: Failed: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    raise
  end

  private

    def load_families(family_id)
      if family_id.present?
        Family.where(id: family_id)
      else
        Family.joins(:policy_versions).distinct
      end
    end

    def refresh_family_actions(family)
      generator = DecisionEngine::TopActionGenerator.new(family)

      clear_expired_actions(family, generator)

      return unless should_generate_actions?(family)

      actions = generator.generate_actions!

      Rails.logger.info("TopActionRefreshJob: Generated #{actions.count} action(s) for family #{family.id}")
    rescue StandardError => e
      Rails.logger.error("TopActionRefreshJob: Failed to refresh actions for family #{family.id}: #{e.message}")
    end

    def clear_expired_actions(family, generator)
      expired_count = family.top_actions.active.where("created_at < ?", 30.days.ago).count

      if expired_count > 0
        generator.clear_expired_actions!
        Rails.logger.info("TopActionRefreshJob: Cleared #{expired_count} expired action(s) for family #{family.id}")
      end
    end

    def should_generate_actions?(family)
      return false unless family.policy_versions.active.exists?

      recent_failure = family.syncs.failed.where("created_at > ?", 1.hour.ago).exists?
      if recent_failure
        Rails.logger.info("TopActionRefreshJob: Skipping family #{family.id} due to recent sync failures")
        return false
      end

      true
    end
end

class GenerateRecommendationsJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer, attempts: 3

  # Generates recommendations for a family using DecisionEngine::RecommendationBuilder
  # This job is idempotent - safe to run multiple times
  #
  # @param family_id [Integer] The ID of the family to generate recommendations for
  def perform(family_id)
    family = Family.find_by(id: family_id)
    return unless family

    Rails.logger.info("GenerateRecommendationsJob: Starting recommendation generation for family #{family_id}")

    policy_version = family.policy_versions.active.first
    if policy_version.nil?
      Rails.logger.info("GenerateRecommendationsJob: No active policy version for family #{family_id}")
      handle_wait_state(family, "No active policy version available")
      return
    end

    unless policy_version.target_percentage_valid?
      Rails.logger.info("GenerateRecommendationsJob: Policy version #{policy_version.id} has invalid target percentages")
      handle_wait_state(family, "Policy target allocations do not sum to 100%")
      return
    end

    data_quality = assess_data_quality(family)
    if data_quality[:issues].any?
      Rails.logger.warn("GenerateRecommendationsJob: Data quality issues detected for family #{family_id}: #{data_quality[:issues].join(', ')}")
    end

    recommendations = build_recommendations(policy_version)

    if recommendations.any?
      update_or_create_top_action(family, recommendations.first)
      Rails.logger.info("GenerateRecommendationsJob: Created #{recommendations.count} recommendation(s) for family #{family_id}")
    else
      handle_wait_state(family, "No recommendations generated - portfolio within target allocations")
      Rails.logger.info("GenerateRecommendationsJob: No recommendations needed for family #{family_id}")
    end
  rescue StandardError => e
    Rails.logger.error("GenerateRecommendationsJob: Failed for family #{family_id}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    raise
  end

  private

    def build_recommendations(policy_version)
      builder = DecisionEngine::RecommendationBuilder.new(policy_version)
      builder.build_recommendations!
    end

    def assess_data_quality(family)
      issues = []

      if family.holdings.none?
        issues << "No holdings data available"
      end

      stale_holdings = family.holdings
        .includes(:security)
        .where("holdings.date < ?", 7.days.ago)
        .count

      if stale_holdings > 0
        issues << "#{stale_holdings} stale holding(s)"
      end

      recent_sync_failures = family.syncs.failed.where("created_at > ?", 24.hours.ago).count
      if recent_sync_failures > 0
        issues << "#{recent_sync_failures} recent sync failure(s)"
      end

      { issues: issues }
    end

    def handle_wait_state(family, reason)
      existing_wait_action = family.top_actions.active.by_type("manual_review").find_by("title LIKE ?", "%Wait%")

      if existing_wait_action.nil?
        family.top_actions.create!(
          action_type: "manual_review",
          title: "Wait - #{reason}",
          description: "Recommendation engine is in wait state: #{reason}. No action required at this time.",
          priority: 2,
          metadata: { reason: reason, wait_state: true }
        )
      end
    end

    def update_or_create_top_action(family, recommendation)
      existing_action = family.top_actions.active.by_type("rebalance_needed").first

      if existing_action
        existing_action.update!(
          title: recommendation.title,
          description: recommendation.description,
          priority: calculate_priority(recommendation),
          metadata: recommendation.details.merge(recommendation_id: recommendation.id)
        )
      else
        family.top_actions.create!(
          action_type: "rebalance_needed",
          title: recommendation.title,
          description: recommendation.description,
          priority: calculate_priority(recommendation),
          metadata: recommendation.details.merge(recommendation_id: recommendation.id)
        )
      end
    end

    def calculate_priority(recommendation)
      drift = recommendation.details.dig("drift_metrics", "total_drift").to_f

      case drift
      when 0...5
        4
      when 5...15
        6
      when 15...25
        8
      else
        10
      end
    end
end

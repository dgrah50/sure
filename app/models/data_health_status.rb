class DataHealthStatus < ApplicationRecord
  belongs_to :family

  enum :connection_state, {
    connected: "connected",
    disconnected: "disconnected",
    stale: "stale",
    error: "error"
  }, default: :connected

  validates :family_id, presence: true
  validates :provider_type, presence: true
  validates :provider_id, presence: true
  validates :price_freshness_score, :holdings_freshness_score, :overall_confidence,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :connected, -> { where(connection_state: "connected") }
  scope :disconnected, -> { where(connection_state: "disconnected") }
  scope :stale, -> { where(connection_state: "stale") }
  scope :error, -> { where(connection_state: "error") }
  scope :for_provider, ->(provider_type) { where(provider_type: provider_type) }

  def healthy?
    connected? && price_freshness_score >= 75 && holdings_freshness_score >= 75
  end

  def status_badge_color
    case connection_state
    when "connected"
      healthy? ? "success" : "warning"
    when "disconnected"
      "secondary"
    when "stale"
      "warning"
    when "error"
      "error"
    else
      "secondary"
    end
  end

  def status_label
    I18n.t("data_health_statuses.states.#{connection_state}")
  end

  def sync_needed?
    last_sync_at.nil? || last_sync_at < 24.hours.ago
  end

  def provider
    @provider ||= provider_type.constantize.find_by(id: provider_id)
  end

  def update_health_from_sync!(sync_success:, error_message: nil)
    if sync_success
      self.connection_state = :connected
      self.error_message = nil
      self.last_sync_at = Time.current
    else
      self.connection_state = :error
      self.error_message = error_message
    end

    calculate_scores!
    save!
  end

  def calculate_scores!
    self.price_freshness_score = calculate_price_freshness
    self.holdings_freshness_score = calculate_holdings_freshness
    self.overall_confidence = calculate_overall_confidence
  end

  class << self
    def refresh_for_family!(family)
      provider_items = gather_provider_items(family)

      provider_items.each do |item|
        status = find_or_initialize_by(
          family: family,
          provider_type: item.class.name,
          provider_id: item.id
        )

        status.update_health_from_provider!(item)
      end

      where(family: family)
    end

    def gather_provider_items(family)
      items = []
      items += family.plaid_items.active.to_a
      items += family.simplefin_items.active.to_a
      items += family.coinbase_items.active.to_a
      items += family.binance_items.active.to_a
      items += family.coinstats_items.active.to_a
      items += family.snaptrade_items.active.to_a
      items += family.mercury_items.active.to_a
      items += family.indexa_capital_items.active.to_a
      items += family.lunchflow_items.active.to_a
      items += family.enable_banking_items.active.to_a
      items
    end
  end

  private

    def update_health_from_provider!(provider_item)
      if provider_item.respond_to?(:status)
        case provider_item.status
        when "requires_update"
          self.connection_state = :stale
        when "good"
          self.connection_state = :connected
        end
      end

      if provider_item.respond_to?(:latest_sync_completed_at)
        self.last_sync_at = provider_item.latest_sync_completed_at
      end

      if provider_item.respond_to?(:scheduled_for_deletion) && provider_item.scheduled_for_deletion?
        self.connection_state = :disconnected
      end

      calculate_scores!
      save!
    end

    def calculate_price_freshness
      return 100 unless family.trades.any?

      freshness_checker = DataHealth::DataFreshness.new
      securities = family.trades.joins(:security).distinct.map(&:security)

      return 100 if securities.none?

      fresh_count = securities.count { |s| freshness_checker.fresh?(s) }
      ((fresh_count.to_f / securities.count) * 100).round
    end

    def calculate_holdings_freshness
      return 100 if family.holdings.none?

      freshness_checker = DataHealth::DataFreshness.new
      fresh_count = family.holdings.count { |h| freshness_checker.fresh?(h) }
      ((fresh_count.to_f / family.holdings.count) * 100).round
    end

    def calculate_overall_confidence
      return 100 if family.holdings.none?

      scorer = DataHealth::ConfidenceScorer.new
      scores = family.holdings.map { |h| scorer.score_holding(h) }

      return 100 if scores.empty?

      (scores.sum.to_f / scores.count).round
    end
end

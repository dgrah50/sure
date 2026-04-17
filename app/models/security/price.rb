class Security::Price < ApplicationRecord
  belongs_to :security

  validates :date, :price, :currency, presence: true
  validates :date, uniqueness: { scope: %i[security_id currency] }
  validates :source_provider, length: { maximum: 255 }, allow_blank: true

  # Confidence levels representing data quality and trust in the price
  # - live: Real-time market data from a reliable provider
  # - fixed: Manually set or calculated price (e.g., USD = 1.00)
  # - stale: Data older than expected freshness threshold
  # - fallback: Interpolated, estimated, or gap-filled data
  # - missing: No data available (lowest confidence, default)
  enum :confidence, { live: 0, fixed: 1, stale: 2, fallback: 3, missing: 4 }, prefix: true

  # Scopes for filtering by confidence level
  scope :confidence_live, -> { where(confidence: :live) }
  scope :confidence_fixed, -> { where(confidence: :fixed) }
  scope :confidence_stale, -> { where(confidence: :stale) }
  scope :confidence_fallback, -> { where(confidence: :fallback) }
  scope :confidence_missing, -> { where(confidence: :missing) }

  # Provisional prices from recent days that should be re-fetched
  # - Must be provisional (gap-filled)
  # - Must be from the last few days (configurable, default 7)
  # - Includes weekends: they get fixed via cascade when weekday prices are fetched
  scope :refetchable_provisional, ->(lookback_days: 7) {
    where(provisional: true)
      .where(date: lookback_days.days.ago.to_date..Date.current)
  }

  # Returns seconds since the price was fetched, or nil if never fetched
  def freshness_seconds
    return nil if fetched_at.nil?

    Time.current - fetched_at
  end

  # Returns true if the price data is stale (exceeds freshness threshold)
  # Default threshold is 1 hour (3600 seconds)
  def stale?(threshold_seconds: 3600)
    return true if fetched_at.nil?

    freshness_seconds > threshold_seconds
  end
end

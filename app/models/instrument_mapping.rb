class InstrumentMapping < ApplicationRecord
  belongs_to :holding, optional: true

  enum :mapped_status, {
    pending: 0,
    approved: 1,
    excluded: 2
  }, default: :pending

  enum :mapping_confidence, {
    low: 0,
    medium: 1,
    high: 2
  }, default: :low

  validates :holding_id, presence: true
  validates :mapped_status, presence: true
  validates :mapping_confidence, presence: true

  scope :approved, -> { where(mapped_status: mapped_statuses[:approved]) }
  scope :pending, -> { where(mapped_status: mapped_statuses[:pending]) }
  scope :excluded, -> { where(mapped_status: mapped_statuses[:excluded]) }

  scope :high_confidence, -> { where(mapping_confidence: mapping_confidences[:high]) }
  scope :medium_confidence, -> { where(mapping_confidence: mapping_confidences[:medium]) }
  scope :low_confidence, -> { where(mapping_confidence: mapping_confidences[:low]) }

  def approved?
    mapped_status == "approved"
  end

  def pending?
    mapped_status == "pending"
  end

  def excluded?
    mapped_status == "excluded"
  end

  def approve!
    update!(mapped_status: :approved, user_approved_at: Time.current)
  end

  def exclude!
    update!(mapped_status: :excluded)
  end

  def reset!
    update!(mapped_status: :pending, user_approved_at: nil)
  end
end

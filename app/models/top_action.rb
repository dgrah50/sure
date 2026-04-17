class TopAction < ApplicationRecord
  belongs_to :family

  ACTION_TYPES = %w[
    rebalance_needed
    policy_drift
    data_quality
    cash_idle
    manual_review
    compliance_issue
  ].freeze

  validates :family, presence: true
  validates :action_type, presence: true, inclusion: { in: ACTION_TYPES }
  validates :title, presence: true
  validates :priority, numericality: { only_integer: true, in: 1..10 }

  scope :active, -> { where(dismissed_at: nil, completed_at: nil) }
  scope :dismissed, -> { where.not(dismissed_at: nil) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :high_priority, -> { where("priority >= ?", 7) }
  scope :by_type, ->(type) { where(action_type: type) }
  scope :for_family, ->(family) { where(family_id: family.id) }
  scope :ordered, -> { order(priority: :desc, created_at: :desc) }

  def dismiss!
    return false if dismissed? || completed?

    update!(dismissed_at: Time.current)
  end

  def complete!
    return false if completed?

    update!(completed_at: Time.current)
  end

  def dismissed?
    dismissed_at.present?
  end

  def completed?
    completed_at.present?
  end

  def expired?
    return false if completed?

    created_at < 30.days.ago
  end
end

class Recommendation < ApplicationRecord
  belongs_to :family
  belongs_to :policy_version, optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  RECOMMENDATION_TYPES = %w[trade rebalance deposit withdraw review].freeze
  STATUSES = %w[pending approved rejected executed].freeze

  validates :family, presence: true
  validates :recommendation_type, presence: true, inclusion: { in: RECOMMENDATION_TYPES }
  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :executed, -> { where(status: "executed") }
  scope :by_type, ->(type) { where(recommendation_type: type) }
  scope :for_family, ->(family) { where(family_id: family.id) }
  scope :for_policy, ->(policy) { where(policy_version_id: policy.id) }
  scope :ordered, -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def executed?
    status == "executed"
  end

  def approve!(user)
    return false unless pending?

    update!(status: "approved", approved_by: user)
  end

  def reject!(user)
    return false unless pending?

    update!(status: "rejected", approved_by: user)
  end

  def execute!
    return false unless approved?

    update!(status: "executed", executed_at: Time.current)
  end

  def trades
    details["trades"] || []
  end

  def total_amount
    details["total_amount"]
  end

  def rationale
    details["rationale"]
  end
end

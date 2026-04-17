class DataQualityCheck < ApplicationRecord
  belongs_to :family

  CHECK_TYPES = %w[
    price_stale
    fx_stale
    holding_missing_basis
    account_sync_failed
    security_missing_classification
    duplicate_holding
    orphaned_transaction
  ].freeze

  STATUSES = %w[pass warning fail].freeze

  validates :check_type, inclusion: { in: CHECK_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :checked_at, presence: true

  scope :active, -> { where(resolved_at: nil) }
  scope :passed, -> { where(status: "pass") }
  scope :warnings, -> { where(status: "warning") }
  scope :failures, -> { where(status: "fail") }
  scope :for_type, ->(type) { where(check_type: type) }

  def pass?
    status == "pass"
  end

  def warning?
    status == "warning"
  end

  def fail?
    status == "fail"
  end

  def resolved?
    resolved_at.present?
  end

  def resolve!
    update!(resolved_at: Time.current)
  end

  def to_problem_hash
    {
      type: check_type,
      status: status,
      details: details,
      checked_at: checked_at,
      severity: status == "fail" ? "high" : (status == "warning" ? "medium" : "low")
    }
  end

  class << self
    def record_check!(family:, check_type:, status:, details: {})
      check = find_or_initialize_by(
        family: family,
        check_type: check_type,
        resolved_at: nil
      )
      check.assign_attributes(
        status: status,
        details: details,
        checked_at: Time.current
      )
      check.save!
      check
    end

    def resolve_checks!(family:, check_type:)
      where(family: family, check_type: check_type, resolved_at: nil)
        .update_all(resolved_at: Time.current)
    end

    def active_problems(family)
      active.where(family: family).where.not(status: "pass")
    end

    def summary_for(family)
      active.where(family: family).group(:status).count
    end
  end
end

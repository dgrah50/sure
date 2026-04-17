class Guardrail < ApplicationRecord
  belongs_to :policy_version

  GUARDRAIL_TYPES = %w[
    drift_threshold
    concentration_limit
    cash_minimum
    cash_maximum
    rebalance_frequency
    tax_loss_harvesting
    sector_concentration
    single_security_limit
    geographic_exposure
  ].freeze

  SEVERITY_LEVELS = %w[warning critical info].freeze

  validates :name, presence: true
  validates :guardrail_type, presence: true, inclusion: { in: GUARDRAIL_TYPES }
  validates :severity, presence: true, inclusion: { in: SEVERITY_LEVELS }
  validates :configuration, presence: true

  scope :enabled, -> { where(enabled: true) }
  scope :for_policy, ->(policy) { where(policy_version_id: policy.id) }
  scope :by_type, ->(type) { where(guardrail_type: type) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :critical, -> { where(severity: "critical") }
  scope :warnings, -> { where(severity: "warning") }

  def warning?
    severity == "warning"
  end

  def critical?
    severity == "critical"
  end

  def info?
    severity == "info"
  end

  def configuration_value(key)
    configuration&.dig(key.to_s)
  end

  def threshold
    configuration_value(:threshold) || configuration_value("threshold")
  end

  def check(value, context = {})
    case guardrail_type
    when "drift_threshold"
      check_drift_threshold(value)
    when "concentration_limit"
      check_concentration_limit(value, context)
    when "cash_minimum"
      check_cash_minimum(value)
    when "cash_maximum"
      check_cash_maximum(value)
    when "single_security_limit"
      check_single_security_limit(value, context)
    else
      { passed: true, message: nil }
    end
  end

  def to_configuration_hash
    {
      "name" => name,
      "type" => guardrail_type,
      "severity" => severity,
      "enabled" => enabled,
      "configuration" => configuration
    }
  end

  private

    def check_drift_threshold(actual_drift)
      limit = threshold.to_f
      passed = actual_drift <= limit

      {
        passed: passed,
        message: passed ? nil : "Drift of #{actual_drift.round(2)}% exceeds threshold of #{limit}%"
      }
    end

    def check_concentration_limit(actual_percentage, context = {})
      limit = threshold.to_f
      sleeve_name = context[:sleeve_name] || name
      passed = actual_percentage <= limit

      {
        passed: passed,
        message: passed ? nil : "#{sleeve_name} concentration of #{actual_percentage.round(2)}% exceeds limit of #{limit}%"
      }
    end

    def check_cash_minimum(cash_percentage)
      minimum = threshold.to_f
      passed = cash_percentage >= minimum

      {
        passed: passed,
        message: passed ? nil : "Cash allocation of #{cash_percentage.round(2)}% is below minimum of #{minimum}%"
      }
    end

    def check_cash_maximum(cash_percentage)
      maximum = threshold.to_f
      passed = cash_percentage <= maximum

      {
        passed: passed,
        message: passed ? nil : "Cash allocation of #{cash_percentage.round(2)}% exceeds maximum of #{maximum}%"
      }
    end

    def check_single_security_limit(security_percentage, context = {})
      limit = threshold.to_f
      security_name = context[:security_name] || "Security"
      passed = security_percentage <= limit

      {
        passed: passed,
        message: passed ? nil : "#{security_name} position of #{security_percentage.round(2)}% exceeds limit of #{limit}%"
      }
    end
end

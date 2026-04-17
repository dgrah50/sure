class PolicyVersion < ApplicationRecord
  belongs_to :family
  belongs_to :created_by, class_name: "User"

  has_many :sleeves, dependent: :destroy
  has_many :guardrails, dependent: :destroy
  has_many :families, foreign_key: :policy_version_id, dependent: :nullify

  validates :name, presence: true
  validates :status, inclusion: { in: %w[draft active archived] }
  validates :effective_date, presence: true, if: :active?

  scope :draft, -> { where(status: "draft") }
  scope :active, -> { where(status: "active") }
  scope :archived, -> { where(status: "archived") }
  scope :for_family, ->(family) { where(family_id: family.id) }
  scope :effective_on, ->(date) { where("effective_date <= ?", date).order(effective_date: :desc) }

  def draft?
    status == "draft"
  end

  def active?
    status == "active"
  end

  def archived?
    status == "archived"
  end

  def activate!
    return false unless draft?

    transaction do
      # Deactivate any currently active policy for this family
      family.policy_versions.active.where.not(id: id).find_each(&:archive!)
      update!(status: "active", effective_date: Date.current)
    end
  end

  def archive!
    return false unless active?

    update!(status: "archived")
  end

  def total_target_percentage
    sleeves.where(parent_sleeve_id: nil).sum(:target_percentage)
  end

  def target_percentage_valid?
    total_target_percentage == 100
  end

  def configuration_with_inheritance
    config = configuration.dup || {}
    config["sleeves"] = sleeve_configuration if sleeves.any?
    config["guardrails"] = guardrail_configuration if guardrails.any?
    config
  end

  private

    def sleeve_configuration
      sleeves.where(parent_sleeve_id: nil).order(:sort_order).map do |sleeve|
        sleeve.to_configuration_hash
      end
    end

    def guardrail_configuration
      guardrails.where(enabled: true).map do |guardrail|
        {
          "name" => guardrail.name,
          "type" => guardrail.guardrail_type,
          "configuration" => guardrail.configuration,
          "severity" => guardrail.severity
        }
      end
    end
end

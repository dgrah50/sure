class DecisionLog < ApplicationRecord
  belongs_to :family
  belongs_to :actor, class_name: "User"

  DECISION_TYPES = %w[action_dismissed recommendation_approved recommendation_rejected manual_override].freeze

  validates :family, presence: true
  validates :actor, presence: true
  validates :decision_type, presence: true, inclusion: { in: DECISION_TYPES }
  validates :reference_type, presence: true
  validates :reference_id, presence: true
  validates :rationale, presence: true

  scope :for_family, ->(family) { where(family_id: family.id) }
  scope :by_type, ->(type) { where(decision_type: type) }
  scope :by_actor, ->(user) { where(actor_id: user.id) }
  scope :for_reference, ->(ref) { where(reference_type: ref.class.name, reference_id: ref.id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :since, ->(date) { where("created_at >= ?", date) }

  def reference
    @reference ||= reference_type.constantize.find_by(id: reference_id)
  end

  def action_dismissed?
    decision_type == "action_dismissed"
  end

  def recommendation_approved?
    decision_type == "recommendation_approved"
  end

  def recommendation_rejected?
    decision_type == "recommendation_rejected"
  end

  def manual_override?
    decision_type == "manual_override"
  end

  def self.log_decision(family:, actor:, decision_type:, reference:, rationale:, metadata: {})
    create!(
      family: family,
      actor: actor,
      decision_type: decision_type,
      reference_type: reference.class.name,
      reference_id: reference.id,
      rationale: rationale,
      metadata: metadata
    )
  end
end

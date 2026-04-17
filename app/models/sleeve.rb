class Sleeve < ApplicationRecord
  belongs_to :policy_version
  belongs_to :parent_sleeve, class_name: "Sleeve", optional: true

  has_many :child_sleeves, class_name: "Sleeve", foreign_key: :parent_sleeve_id, dependent: :destroy

  validates :name, presence: true
  validates :target_percentage, presence: true, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }
  validates :min_percentage, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100,
    allow_nil: true
  }
  validates :max_percentage, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100,
    allow_nil: true
  }
  validates :sort_order, numericality: { only_integer: true }, allow_nil: true

  validate :percentage_bounds_consistency
  validate :parent_belongs_to_same_policy
  validate :no_circular_nesting

  scope :root, -> { where(parent_sleeve_id: nil) }
  scope :for_policy, ->(policy) { where(policy_version_id: policy.id) }
  scope :ordered, -> { order(:sort_order, :created_at) }
  scope :by_target_desc, -> { order(target_percentage: :desc) }

  def root?
    parent_sleeve_id.nil?
  end

  def leaf?
    child_sleeves.empty?
  end

  def depth
    return 0 if root?

    parent_sleeve.depth + 1
  end

  def ancestors
    return [] if root?

    [parent_sleeve] + parent_sleeve.ancestors
  end

  def descendants
    child_sleeves.flat_map { |child| [child] + child.descendants }
  end

  def siblings
    policy_version.sleeves.where(parent_sleeve_id: parent_sleeve_id).where.not(id: id)
  end

  def effective_min_percentage
    min_percentage || 0
  end

  def effective_max_percentage
    max_percentage || 100
  end

  def target_in_range?
    target_percentage >= effective_min_percentage &&
      target_percentage <= effective_max_percentage
  end

  def children_target_percentage
    child_sleeves.sum(:target_percentage)
  end

  def children_target_valid?
    return true if leaf?

    children_target_percentage == target_percentage
  end

  def to_configuration_hash
    hash = {
      "name" => name,
      "target_percentage" => target_percentage.to_f,
      "color" => color
    }

    hash["min_percentage"] = min_percentage.to_f if min_percentage.present?
    hash["max_percentage"] = max_percentage.to_f if max_percentage.present?

    if child_sleeves.any?
      hash["children"] = child_sleeves.ordered.map(&:to_configuration_hash)
    end

    hash
  end

  private

    def percentage_bounds_consistency
      return if min_percentage.nil? || max_percentage.nil?
      return if min_percentage <= max_percentage

      errors.add(:min_percentage, "must be less than or equal to max percentage")
    end

    def parent_belongs_to_same_policy
      return if parent_sleeve.nil?
      return if parent_sleeve.policy_version_id == policy_version_id

      errors.add(:parent_sleeve, "must belong to the same policy version")
    end

    def no_circular_nesting
      return if parent_sleeve.nil?
      return unless parent_sleeve.ancestors.include?(self) || parent_sleeve == self

      errors.add(:parent_sleeve, "cannot create circular nesting")
    end
end

# Manages Lunchflow connections for a Family.
# Extracted from LunchflowConnectable concern to respect Single Responsibility Principle.
class Family::LunchflowService < Family::ProviderService
  def self.item_association_name
    :lunchflow_items
  end

  def self.item_class
    LunchflowItem
  end

  # Families can now configure their own Lunchflow credentials
  def can_connect?
    true
  end

  def create_item!(api_key:, base_url: nil, item_name: nil)
    lunchflow_item = family.lunchflow_items.create!(
      name: item_name || "Lunch Flow Connection",
      api_key: api_key,
      base_url: base_url
    )

    lunchflow_item.sync_later

    lunchflow_item
  end

  def has_credentials?
    family.lunchflow_items.where.not(api_key: nil).exists?
  end
end

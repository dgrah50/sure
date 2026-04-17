# Manages Mercury connections for a Family.
# Extracted from MercuryConnectable concern to respect Single Responsibility Principle.
class Family::MercuryService < Family::ProviderService
  def self.item_association_name
    :mercury_items
  end

  def self.item_class
    MercuryItem
  end

  # Families can configure their own Mercury credentials
  def can_connect?
    true
  end

  def create_item!(token:, base_url: nil, item_name: nil)
    mercury_item = family.mercury_items.create!(
      name: item_name || "Mercury Connection",
      token: token,
      base_url: base_url
    )

    mercury_item.sync_later

    mercury_item
  end

  def has_credentials?
    family.mercury_items.where.not(token: nil).exists?
  end
end

# Manages Coinbase connections for a Family.
# Extracted from CoinbaseConnectable concern to respect Single Responsibility Principle.
class Family::CoinbaseService < Family::ProviderService
  def self.item_association_name
    :coinbase_items
  end

  def self.item_class
    CoinbaseItem
  end

  # Families can configure their own Coinbase credentials
  def can_connect?
    true
  end

  def create_item!(api_key:, api_secret:, item_name: nil)
    coinbase_item = family.coinbase_items.create!(
      name: item_name || "Coinbase",
      api_key: api_key,
      api_secret: api_secret
    )

    coinbase_item.sync_later

    coinbase_item
  end

  def has_credentials?
    family.coinbase_items.where.not(api_key: nil).exists?
  end
end

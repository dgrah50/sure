# frozen_string_literal: true

# Manages CoinStats connections for a Family.
# Extracted from CoinstatsConnectable concern to respect Single Responsibility Principle.
class Family::CoinstatsService < Family::ProviderService
  def self.item_association_name
    :coinstats_items
  end

  def self.item_class
    CoinstatsItem
  end

  # Families can configure their own Coinstats credentials
  def can_connect?
    true
  end

  # Creates a new CoinStats connection and triggers initial sync.
  # @param api_key [String] CoinStats API key
  # @param item_name [String, nil] Optional display name for the connection
  # @return [CoinstatsItem] The created connection
  def create_item!(api_key:, item_name: nil)
    coinstats_item = family.coinstats_items.create!(
      name: item_name || "CoinStats Connection",
      api_key: api_key
    )

    coinstats_item.sync_later

    coinstats_item
  end

  # @return [Boolean] Whether the family has any configured CoinStats connections
  def has_credentials?
    family.coinstats_items.where.not(api_key: nil).exists?
  end
end

# frozen_string_literal: true

# Manages Binance connections for a Family.
# Extracted from BinanceConnectable concern to respect Single Responsibility Principle.
class Family::BinanceService < Family::ProviderService
  def self.item_association_name
    :binance_items
  end

  def self.item_class
    BinanceItem
  end

  def can_connect?
    true
  end

  def create_item!(api_key:, api_secret:, item_name: nil)
    item = family.binance_items.create!(
      name: item_name || "Binance",
      api_key: api_key,
      api_secret: api_secret
    )
    item.sync_later
    item
  end

  def has_credentials?
    family.binance_items.where.not(api_key: nil).exists?
  end
end

# Manages Snaptrade connections for a Family.
# Extracted from SnaptradeConnectable concern to respect Single Responsibility Principle.
class Family::SnaptradeService < Family::ProviderService
  def self.item_association_name
    :snaptrade_items
  end

  def self.item_class
    SnaptradeItem
  end

  # Families can configure their own Snaptrade credentials
  def can_connect?
    true
  end

  def create_item!(client_id:, consumer_key:, snaptrade_user_secret:, snaptrade_user_id: nil, item_name: nil)
    snaptrade_item = family.snaptrade_items.create!(
      name: item_name || "Snaptrade Connection",
      client_id: client_id,
      consumer_key: consumer_key,
      snaptrade_user_id: snaptrade_user_id,
      snaptrade_user_secret: snaptrade_user_secret
    )

    snaptrade_item.sync_later

    snaptrade_item
  end

  def has_credentials?
    family.snaptrade_items.where.not(client_id: nil).exists?
  end
end

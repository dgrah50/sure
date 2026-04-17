# Manages SimpleFIN connections for a Family.
# Extracted from SimplefinConnectable concern to respect Single Responsibility Principle.
class Family::SimplefinService < Family::ProviderService
  def self.item_association_name
    :simplefin_items
  end

  def self.item_class
    SimplefinItem
  end

  # SimpleFIN doesn't have regional restrictions like Plaid
  def can_connect?
    true
  end

  def create_item!(setup_token:, item_name: nil)
    simplefin_provider = Provider::Simplefin.new
    access_url = simplefin_provider.claim_access_url(setup_token)

    simplefin_item = family.simplefin_items.create!(
      name: item_name || "SimpleFin Connection",
      access_url: access_url
    )

    simplefin_item.sync_later

    simplefin_item
  end
end

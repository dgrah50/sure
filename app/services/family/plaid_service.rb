# Manages Plaid connections for a Family.
# Extracted from PlaidConnectable concern to respect Single Responsibility Principle.
class Family::PlaidService < Family::ProviderService
  def self.item_association_name
    :plaid_items
  end

  def self.item_class
    PlaidItem
  end

  # If Plaid provider is configured for US region
  def can_connect_us?
    plaid(:us).present?
  end

  # If Plaid provider is configured and user is in the EU region
  def can_connect_eu?
    plaid(:eu).present? && family.eu?
  end

  # For compatibility with adapter interface
  alias_method :can_connect?, :can_connect_us?

  def create_item!(public_token:, item_name:, region:)
    public_token_response = plaid(region).exchange_public_token(public_token)

    plaid_item = family.plaid_items.create!(
      name: item_name,
      plaid_id: public_token_response.item_id,
      access_token: public_token_response.access_token,
      plaid_region: region
    )

    plaid_item.sync_later

    plaid_item
  end

  def get_link_token(webhooks_url:, redirect_url:, accountable_type: nil, region: :us, access_token: nil)
    return nil unless plaid(region)

    plaid(region).get_link_token(
      user_id: family.id,
      webhooks_url: webhooks_url,
      redirect_url: redirect_url,
      accountable_type: accountable_type,
      access_token: access_token
    ).link_token
  end

  private

    def plaid(region)
      Provider::Registry.plaid_provider_for_region(region)
    end
end

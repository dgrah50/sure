# Manages Enable Banking connections for a Family.
# Extracted from EnableBankingConnectable concern to respect Single Responsibility Principle.
class Family::EnableBankingService < Family::ProviderService
  def self.item_association_name
    :enable_banking_items
  end

  def self.item_class
    EnableBankingItem
  end

  # Families can configure their own Enable Banking credentials
  def can_connect?
    true
  end

  def create_item!(country_code:, application_id:, client_certificate:, item_name: nil)
    enable_banking_item = family.enable_banking_items.create!(
      name: item_name || "Enable Banking Connection",
      country_code: country_code,
      application_id: application_id,
      client_certificate: client_certificate
    )

    enable_banking_item
  end

  def has_credentials?
    family.enable_banking_items.where.not(client_certificate: nil).exists?
  end

  def has_session?
    family.enable_banking_items.where.not(session_id: nil).exists?
  end
end

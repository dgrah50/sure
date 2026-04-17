# Base class for all provider adapters. Subclasses must implement #provider_name.
class Provider::Base
  attr_reader :provider_account, :account

  def initialize(provider_account, account: nil)
    @provider_account = provider_account
    @account = account || provider_account.account
  end

  def provider_name
    raise NotImplementedError, "#{self.class} must implement #provider_name"
  end

  # Defines which account types this provider supports
  # Override in subclasses to specify supported account types
  # @return [Array<String>] Array of account type class names (e.g., ["Depository", "CreditCard"])
  def self.supported_account_types
    []
  end

  # Returns provider connection configurations
  # Override in subclasses to provide connection metadata for UI
  # @param family [Family] The family to check connection availability for
  # @return [Array<Hash>] Array of connection configurations with keys:
  #   - key: Unique identifier (e.g., "lunchflow", "plaid_us")
  #   - name: Display name (e.g., "Lunch Flow", "Plaid")
  #   - description: User-facing description
  #   - can_connect: Boolean, whether family can connect to this provider
  #   - new_account_path: Proc that generates path for new account flow
  #   - existing_account_path: Proc that generates path for linking existing account
  def self.connection_configs(family:)
    []
  end

  def provider_type
    provider_account.class.name
  end

  # Whether this provider allows deletion of holdings
  # Override in subclass if provider supports holdings deletion
  # @return [Boolean] True if holdings can be deleted, false otherwise
  def can_delete_holdings?
    false
  end

  # Provider-specific raw data payload
  # @return [Hash, nil] The raw payload from the provider
  def raw_payload
    provider_account.raw_payload
  end

  # Returns metadata about this provider and account
  # Automatically includes institution metadata if the adapter includes Provider::InstitutionMetadata
  # @return [Hash] Metadata hash
  def metadata
    base_metadata = {
      provider_name: provider_name,
      provider_type: provider_type
    }

    # Include institution metadata if the module is included
    if respond_to?(:institution_metadata)
      base_metadata.merge!(institution: institution_metadata)
    end

    base_metadata
  end
end

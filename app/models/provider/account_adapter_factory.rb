class Provider::AccountAdapterFactory
  class << self
    # Creates an adapter for a given AccountProvider record
    # This factory decouples AccountProvider from Provider::Factory
    # @param account_provider [AccountProvider] The account provider record
    # @return [Provider::Base, nil] An adapter instance or nil if provider is nil
    def create(account_provider)
      return nil if account_provider.nil? || account_provider.provider.nil?

      Provider::Factory.create_adapter(
        account_provider.provider,
        account: account_provider.account
      )
    end
  end
end

# Manages Plaid US configuration loading and Rails.application.config.plaid setup.
# Separated from PlaidAdapter to maintain Single Responsibility Principle.
class Provider::PlaidConfiguration
  include Provider::Configurable

  # Mutex for thread-safe configuration loading
  # Initialized at class load time to avoid race conditions on mutex creation
  @config_mutex = Mutex.new

  # Configuration for Plaid US
  configure do
    description <<~DESC
      Setup instructions:
      1. Visit the [Plaid Dashboard](https://dashboard.plaid.com/team/keys) to get your API credentials
      2. Your Client ID and Secret Key are required to enable Plaid bank sync for US/CA banks
      3. For production use, set environment to 'production', for testing use 'sandbox'
    DESC

    field :client_id,
          label: "Client ID",
          required: false,
          env_key: "PLAID_CLIENT_ID",
          description: "Your Plaid Client ID from the Plaid Dashboard"

    field :secret,
          label: "Secret Key",
          required: false,
          secret: true,
          env_key: "PLAID_SECRET",
          description: "Your Plaid Secret from the Plaid Dashboard"

    field :environment,
          label: "Environment",
          required: false,
          env_key: "PLAID_ENV",
          default: "sandbox",
          description: "Plaid environment: sandbox, development, or production"

    # Plaid requires both client_id and secret to be configured
    configured_check { get_value(:client_id).present? && get_value(:secret).present? }
  end

  # Thread-safe lazy loading of Plaid US configuration
  # Ensures configuration is loaded exactly once even under concurrent access
  def self.ensure_configuration_loaded
    # Fast path: return immediately if already loaded (no lock needed)
    return if Rails.application.config.plaid.present?

    # Slow path: acquire lock and reload if still needed
    @config_mutex.synchronize do
      # Double-check after acquiring lock (another thread may have loaded it)
      return if Rails.application.config.plaid.present?

      reload_configuration
    end
  end

  # Reload Plaid US configuration when settings are updated
  def self.reload_configuration
    client_id = config_value(:client_id).presence || ENV["PLAID_CLIENT_ID"]
    secret = config_value(:secret).presence || ENV["PLAID_SECRET"]
    environment = config_value(:environment).presence || ENV["PLAID_ENV"] || "sandbox"

    if client_id.present? && secret.present?
      Rails.application.config.plaid = Plaid::Configuration.new
      Rails.application.config.plaid.server_index = Plaid::Configuration::Environment[environment]
      Rails.application.config.plaid.api_key["PLAID-CLIENT-ID"] = client_id
      Rails.application.config.plaid.api_key["PLAID-SECRET"] = secret
    else
      Rails.application.config.plaid = nil
    end
  end
end

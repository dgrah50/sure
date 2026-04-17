class Provider::Registry
  include ActiveModel::Validations

  Error = Class.new(StandardError)

  CONCEPTS = %i[exchange_rates securities llm]

  validates :concept, inclusion: { in: CONCEPTS }

  # Configuration struct for provider settings
  Config = Struct.new(
    :stripe_secret_key,
    :stripe_webhook_secret,
    :twelve_data_api_key,
    :openai_access_token,
    :openai_uri_base,
    :openai_model,
    :tiingo_api_key,
    :eodhd_api_key,
    :alpha_vantage_api_key,
    keyword_init: true
  ) do
    def self.from_env_and_settings
      new(
        stripe_secret_key: ENV["STRIPE_SECRET_KEY"],
        stripe_webhook_secret: ENV["STRIPE_WEBHOOK_SECRET"],
        twelve_data_api_key: ENV["TWELVE_DATA_API_KEY"].presence || Setting.twelve_data_api_key,
        openai_access_token: ENV["OPENAI_ACCESS_TOKEN"].presence || Setting.openai_access_token,
        openai_uri_base: ENV["OPENAI_URI_BASE"].presence || Setting.openai_uri_base,
        openai_model: ENV["OPENAI_MODEL"].presence || Setting.openai_model,
        tiingo_api_key: ENV["TIINGO_API_KEY"].presence || Setting.tiingo_api_key,
        eodhd_api_key: ENV["EODHD_API_KEY"].presence || Setting.eodhd_api_key,
        alpha_vantage_api_key: ENV["ALPHA_VANTAGE_API_KEY"].presence || Setting.alpha_vantage_api_key
      )
    end
  end

  class << self
    def for_concept(concept)
      new(concept.to_sym)
    end

    def get_provider(name)
      instance.send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end

    def plaid_provider_for_region(region)
      region.to_sym == :us ? instance.plaid_us : instance.plaid_eu
    end

    # Global instance with default configuration - allows class-level access
    def instance
      @instance ||= new(nil)
    end

    # Reset the global instance (useful for testing)
    def reset_instance!
      @instance = nil
    end

    # Configure the global instance with a custom config
    def configure(config)
      @instance = new(nil, config)
    end

    private
      def stripe
        instance.send(:stripe)
      end

      def twelve_data
        instance.send(:twelve_data)
      end

      def plaid_us
        Provider::PlaidConfiguration.ensure_configuration_loaded
        instance.send(:plaid_us)
      end

      def plaid_eu
        Provider::PlaidEuAdapter.ensure_configuration_loaded
        instance.send(:plaid_eu)
      end

      def github
        instance.send(:github)
      end

      def openai
        instance.send(:openai)
      end

      def yahoo_finance
        instance.send(:yahoo_finance)
      end

      def tiingo
        instance.send(:tiingo)
      end

      def eodhd
        instance.send(:eodhd)
      end

      def alpha_vantage
        instance.send(:alpha_vantage)
      end

      def mfapi
        instance.send(:mfapi)
      end

      def binance_public
        instance.send(:binance_public)
      end
  end

  def initialize(concept, config = nil)
    @concept = concept
    @config = config || Config.from_env_and_settings
    validate! if concept.present?
  end

  def providers
    available_providers.map { |p| send(p) }.compact
  end

  # Returns the list of provider key names (symbols) registered for this concept.
  def provider_keys
    available_providers
  end

  def get_provider(name)
    provider_method = available_providers.find { |p| p == name.to_sym }

    raise Error.new("Provider '#{name}' not found for concept: #{concept}") unless provider_method.present?

    send(provider_method)
  end

  private
    attr_reader :concept, :config

    def available_providers
      case concept
      when :exchange_rates
        %i[twelve_data yahoo_finance]
      when :securities
        %i[twelve_data yahoo_finance tiingo eodhd alpha_vantage mfapi binance_public]
      when :llm
        %i[openai]
      else
        %i[plaid_us plaid_eu github openai]
      end
    end

    def stripe
      secret_key = config.stripe_secret_key
      webhook_secret = config.stripe_webhook_secret

      return nil unless secret_key.present? && webhook_secret.present?

      Provider::Stripe.new(secret_key:, webhook_secret:)
    end

    def twelve_data
      api_key = config.twelve_data_api_key

      return nil unless api_key.present?

      Provider::TwelveData.new(api_key)
    end

    def plaid_us
      plaid_configuration = Rails.application.config.plaid

      return nil unless plaid_configuration.present?

      Provider::Plaid.new(plaid_configuration, region: :us)
    end

    def plaid_eu
      plaid_configuration = Rails.application.config.plaid_eu

      return nil unless plaid_configuration.present?

      Provider::Plaid.new(plaid_configuration, region: :eu)
    end

    def github
      Provider::Github.new
    end

    def openai
      access_token = config.openai_access_token

      return nil unless access_token.present?

      uri_base = config.openai_uri_base
      model = config.openai_model

      if uri_base.present? && model.blank?
        Rails.logger.error("Custom OpenAI provider configured without a model; please set OPENAI_MODEL or Setting.openai_model")
        return nil
      end

      Provider::Openai.new(access_token, uri_base: uri_base, model: model)
    end

    def yahoo_finance
      Provider::YahooFinance.new
    end

    def tiingo
      api_key = config.tiingo_api_key

      return nil unless api_key.present?

      Provider::Tiingo.new(api_key)
    end

    def eodhd
      api_key = config.eodhd_api_key

      return nil unless api_key.present?

      Provider::Eodhd.new(api_key)
    end

    def alpha_vantage
      api_key = config.alpha_vantage_api_key

      return nil unless api_key.present?

      Provider::AlphaVantage.new(api_key)
    end

    def mfapi
      Provider::Mfapi.new
    end

    def binance_public
      Provider::BinancePublic.new
    end
end

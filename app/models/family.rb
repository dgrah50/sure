class Family < ApplicationRecord
  include Syncable, Subscribeable, VectorSearchable

  DATE_FORMATS = [
    [ "MM-DD-YYYY", "%m-%d-%Y" ],
    [ "DD.MM.YYYY", "%d.%m.%Y" ],
    [ "DD-MM-YYYY", "%d-%m-%Y" ],
    [ "YYYY-MM-DD", "%Y-%m-%d" ],
    [ "DD/MM/YYYY", "%d/%m/%Y" ],
    [ "YYYY/MM/DD", "%Y/%m/%d" ],
    [ "MM/DD/YYYY", "%m/%d/%Y" ],
    [ "D/MM/YYYY", "%e/%m/%Y" ],
    [ "YYYY.MM.DD", "%Y.%m.%d" ],
    [ "YYYYMMDD", "%Y%m%d" ]
  ].freeze


  MONIKERS = [ "Family", "Group" ].freeze
  ASSISTANT_TYPES = %w[builtin external].freeze
  SHARING_DEFAULTS = %w[shared private].freeze

  has_many :users, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :family_exports, dependent: :destroy

  # Provider items - associations stay in the model, logic moves to services
  has_many :plaid_items, dependent: :destroy
  has_many :simplefin_items, dependent: :destroy
  has_many :lunchflow_items, dependent: :destroy
  has_many :enable_banking_items, dependent: :destroy
  has_many :coinbase_items, dependent: :destroy
  has_many :binance_items, dependent: :destroy
  has_many :coinstats_items, dependent: :destroy
  has_many :snaptrade_items, dependent: :destroy
  has_many :mercury_items, dependent: :destroy
  has_many :indexa_capital_items, dependent: :destroy

  has_many :entries, through: :accounts
  has_many :transactions, through: :accounts
  has_many :trades, through: :accounts
  has_many :holdings, through: :accounts

  has_many :tags, dependent: :destroy

  has_many :llm_usages, dependent: :destroy

  has_many :data_quality_checks, dependent: :destroy
  has_one :data_quality_summary, dependent: :destroy

  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }
  validates :date_format, inclusion: { in: DATE_FORMATS.map(&:last) }
  validates :month_start_day, inclusion: { in: 1..28 }
  validates :moniker, inclusion: { in: MONIKERS }
  validates :assistant_type, inclusion: { in: ASSISTANT_TYPES }
  validates :default_account_sharing, inclusion: { in: SHARING_DEFAULTS }

  before_validation :normalize_enabled_currencies!

  def primary_currency_code
    normalize_currency_code(currency) || "USD"
  end

  def single_currency?
    enabled_currency_codes.size <= 1
  end

  def custom_enabled_currencies?
    enabled_currencies.present?
  end

  def enabled_currency_codes(extra: [])
    selected_codes = if custom_enabled_currencies?
      [ primary_currency_code, *Array(enabled_currencies) ]
    else
      Money::Currency.as_options.map(&:iso_code)
    end

    normalize_currency_codes([ *selected_codes, *Array(extra) ])
  end

  def enabled_currency_objects(extra: [])
    enabled_currency_codes(extra:).map { |code| Money::Currency.new(code) }
  end

  def secondary_enabled_currency_objects(extra: [])
    enabled_currency_objects(extra:).reject { |currency| currency.iso_code == primary_currency_code }
  end


  def moniker_label
    moniker.presence || "Family"
  end

  def moniker_label_plural
    moniker_label == "Group" ? "Groups" : "Families"
  end

  def share_all_by_default?
    default_account_sharing == "shared"
  end

  def uses_custom_month_start?
    month_start_day != 1
  end

  def custom_month_start_for(date)
    if date.day >= month_start_day
      Date.new(date.year, date.month, month_start_day)
    else
      previous_month = date - 1.month
      Date.new(previous_month.year, previous_month.month, month_start_day)
    end
  end

  def custom_month_end_for(date)
    start_date = custom_month_start_for(date)
    next_month_start = start_date + 1.month
    next_month_start - 1.day
  end

  def current_custom_month_period
    start_date = custom_month_start_for(Date.current)
    end_date = custom_month_end_for(Date.current)
    Period.custom(start_date: start_date, end_date: end_date)
  end

  def balance_sheet(user: Current.user)
    BalanceSheet.new(self, user: user)
  end

  def investment_statement(user: Current.user)
    InvestmentStatement.new(self, user: user)
  end

  def eu?
    country != "US" && country != "CA"
  end

  def requires_securities_data_provider?
    # If family has any trades, they need a provider for historical prices
    trades.any?
  end

  def requires_exchange_rates_data_provider?
    # If family has any accounts not denominated in the family's currency, they need a provider for historical exchange rates
    return true if accounts.where.not(currency: self.currency).any?

    # If family has any entries in different currencies, they need a provider for historical exchange rates
    uniq_currencies = entries.pluck(:currency).uniq
    return true if uniq_currencies.count > 1
    return true if uniq_currencies.count > 0 && uniq_currencies.first != self.currency

    false
  end

  def missing_data_provider?
    (requires_securities_data_provider? && Security.provider.nil?) ||
    (requires_exchange_rates_data_provider? && ExchangeRate.provider.nil?)
  end

  # Returns securities with plan restrictions for a specific provider
  # @param provider [String] The provider name (e.g., "TwelveData")
  # @return [Array<Hash>] Array of hashes with ticker, name, required_plan, provider
  def securities_with_plan_restrictions(provider:)
    security_ids = trades.joins(:security).pluck("securities.id").uniq
    return [] if security_ids.empty?

    restrictions = Security.plan_restrictions_for(security_ids, provider: provider)
    return [] if restrictions.empty?

    Security.where(id: restrictions.keys).map do |security|
      restriction = restrictions[security.id]
      {
        ticker: security.ticker,
        name: security.name,
        required_plan: restriction[:required_plan],
        provider: restriction[:provider]
      }
    end
  end

  def oldest_entry_date
    entries.order(:date).first&.date || Date.current
  end

  # Used for invalidating family / balance sheet related aggregation queries
  def build_cache_key(key, invalidate_on_data_updates: false)
    # Our data sync process updates this timestamp whenever any family account successfully completes a data update.
    # By including it in the cache key, we can expire caches every time family account data changes.
    data_invalidation_key = invalidate_on_data_updates ? latest_sync_completed_at : nil

    [
      id,
      key,
      data_invalidation_key,
      accounts.maximum(:updated_at)
    ].compact.join("_")
  end

  # Used for invalidating entry related aggregation queries
  def entries_cache_version
    @entries_cache_version ||= begin
      ts = entries.maximum(:updated_at)
      ts.present? ? ts.to_i : 0
    end
  end

  def self_hoster?
    Rails.application.config.app_mode.self_hosted?
  end

  # Provider Service Delegations
  # These methods delegate to service classes to avoid bloating the model
  # with provider-specific logic, respecting Single Responsibility Principle.

  # Plaid
  delegate :can_connect_us?, :can_connect_eu?, :create_plaid_item!, :get_link_token,
           to: :plaid_service
  alias_method :can_connect_plaid_us?, :can_connect_us?
  alias_method :can_connect_plaid_eu?, :can_connect_eu?

  # SimpleFIN
  delegate :can_connect?, :create_simplefin_item!,
           to: :simplefin_service
  alias_method :can_connect_simplefin?, :can_connect?

  # Lunchflow
  delegate :can_connect?, :create_lunchflow_item!, :has_credentials?,
           to: :lunchflow_service
  alias_method :can_connect_lunchflow?, :can_connect?
  alias_method :has_lunchflow_credentials?, :has_credentials?

  # Enable Banking
  delegate :can_connect?, :create_enable_banking_item!, :has_credentials?, :has_session?,
           to: :enable_banking_service
  alias_method :can_connect_enable_banking?, :can_connect?
  alias_method :has_enable_banking_credentials?, :has_credentials?
  alias_method :has_enable_banking_session?, :has_session?

  # Coinbase
  delegate :can_connect?, :create_coinbase_item!, :has_credentials?,
           to: :coinbase_service
  alias_method :can_connect_coinbase?, :can_connect?
  alias_method :has_coinbase_credentials?, :has_credentials?

  # Binance
  delegate :can_connect?, :create_binance_item!, :has_credentials?,
           to: :binance_service
  alias_method :can_connect_binance?, :can_connect?
  alias_method :has_binance_credentials?, :has_credentials?

  # Coinstats
  delegate :can_connect?, :create_coinstats_item!, :has_credentials?,
           to: :coinstats_service
  alias_method :can_connect_coinstats?, :can_connect?
  alias_method :has_coinstats_credentials?, :has_credentials?

  # Snaptrade
  delegate :can_connect?, :create_snaptrade_item!, :has_credentials?,
           to: :snaptrade_service
  alias_method :can_connect_snaptrade?, :can_connect?
  alias_method :has_snaptrade_credentials?, :has_credentials?

  # Mercury
  delegate :can_connect?, :create_mercury_item!, :has_credentials?,
           to: :mercury_service
  alias_method :can_connect_mercury?, :can_connect?
  alias_method :has_mercury_credentials?, :has_credentials?

  # Indexa Capital
  delegate :can_connect?, :create_indexa_capital_item!, :has_credentials?,
           to: :indexa_capital_service
  alias_method :can_connect_indexa_capital?, :can_connect?
  alias_method :has_indexa_capital_credentials?, :has_credentials?

  private
    def plaid_service
      @plaid_service ||= Family::PlaidService.new(self)
    end

    def simplefin_service
      @simplefin_service ||= Family::SimplefinService.new(self)
    end

    def lunchflow_service
      @lunchflow_service ||= Family::LunchflowService.new(self)
    end

    def enable_banking_service
      @enable_banking_service ||= Family::EnableBankingService.new(self)
    end

    def coinbase_service
      @coinbase_service ||= Family::CoinbaseService.new(self)
    end

    def binance_service
      @binance_service ||= Family::BinanceService.new(self)
    end

    def coinstats_service
      @coinstats_service ||= Family::CoinstatsService.new(self)
    end

    def snaptrade_service
      @snaptrade_service ||= Family::SnaptradeService.new(self)
    end

    def mercury_service
      @mercury_service ||= Family::MercuryService.new(self)
    end

    def indexa_capital_service
      @indexa_capital_service ||= Family::IndexaCapitalService.new(self)
    end

    def normalize_enabled_currencies!
      if enabled_currencies.blank?
        self.enabled_currencies = nil
        return
      end

      normalized_codes = normalize_currency_codes([ primary_currency_code, *Array(enabled_currencies) ])
      all_codes = Money::Currency.as_options.map(&:iso_code)
      all_selected = normalized_codes.size == all_codes.size && (normalized_codes - all_codes).empty?
      self.enabled_currencies = all_selected ? nil : normalized_codes
    end

    def normalize_currency_codes(values)
      Array(values).filter_map { |value| normalize_currency_code(value) }.uniq
    end

    def normalize_currency_code(value)
      return if value.blank?

      Money::Currency.new(value).iso_code
    rescue Money::Currency::UnknownCurrencyError, ArgumentError
      nil
    end
end

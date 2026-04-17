class ExchangeRate < ApplicationRecord
  include Provided

  validates :from_currency, :to_currency, :date, :rate, presence: true
  validates :date, uniqueness: { scope: %i[from_currency to_currency] }

  # Returns true if this is a fixed rate (same currency conversion)
  def fixed_rate?
    from_currency == to_currency
  end

  class << self
    # Returns a fixed rate when converting a currency to itself (e.g., USD -> USD = 1.0)
    # Returns nil if from_currency != to_currency (needs provider lookup)
    def fixed_rate_for(from_currency, to_currency)
      return nil unless from_currency == to_currency
      1.0
    end

    # Returns the fixed rate for USD (1.0)
    # USD is the reference currency for all exchange rates
    def usd_rate
      1.0
    end
  end
end

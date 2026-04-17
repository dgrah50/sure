module DataHealth
  class DataFreshness
    # Thresholds for determining if data is fresh, stale, or critical
    FRESHNESS_THRESHOLDS = {
      securities: {
        fresh: 1.day,
        warning: 3.days,
        critical: 7.days
      },
      exchange_rates: {
        fresh: 1.day,
        warning: 3.days,
        critical: 7.days
      },
      holdings: {
        fresh: 1.day,
        warning: 7.days,
        critical: 30.days
      },
      account_balances: {
        fresh: 1.day,
        warning: 3.days,
        critical: 7.days
      }
    }.freeze

    # Check if a record is fresh based on its type
    def fresh?(record)
      return false if record.nil?

      case record.class.name
      when "Security"
        security_fresh?(record)
      when "ExchangeRate"
        exchange_rate_fresh?(record)
      when "Holding"
        holding_fresh?(record)
      when "Balance"
        balance_fresh?(record)
      when "Account"
        account_fresh?(record)
      else
        # Default to checking updated_at
        record.updated_at.present? && record.updated_at > 1.day.ago
      end
    end

    # Get all stale records from a scope
    def stale_records(scope)
      return scope.none unless scope.respond_to?(:where)

      model_class = scope.klass
      threshold = freshness_threshold_for(model_class.name)

      scope.where("updated_at < ? OR updated_at IS NULL", threshold[:fresh].ago)
    end

    # Calculate freshness score (0-100) for a collection
    def freshness_score(scope)
      return 100 if scope.none?

      total = scope.count
      fresh_count = scope.count { |r| fresh?(r) }

      ((fresh_count.to_f / total) * 100).round
    end

    # Get freshness status for a record
    def status(record)
      return :unknown if record.nil?

      freshness_info(record)[:status]
    end

    # Get detailed freshness information
    def freshness_info(record)
      return { status: :unknown, age: nil, threshold: nil } if record.nil?

      age = calculate_age(record)
      thresholds = thresholds_for(record)

      status = if age.nil?
        :unknown
      elsif age <= thresholds[:fresh]
        :fresh
      elsif age <= thresholds[:warning]
        :warning
      elsif age <= thresholds[:critical]
        :stale
      else
        :critical
      end

      {
        status: status,
        age: age,
        threshold: thresholds,
        record_type: record.class.name,
        last_updated: last_updated_for(record)
      }
    end

    # Get family-wide freshness summary
    def family_summary(family)
      {
        securities: {
          score: securities_freshness_score(family),
          stale_count: stale_securities(family).count,
          total_count: traded_securities(family).count
        },
        exchange_rates: {
          score: exchange_rates_freshness_score(family),
          stale_count: stale_exchange_rates(family).count,
          total_count: needed_exchange_rates(family).count
        },
        holdings: {
          score: holdings_freshness_score(family),
          stale_count: stale_holdings(family).count,
          total_count: family.holdings.count
        },
        accounts: {
          score: accounts_freshness_score(family),
          stale_count: stale_accounts(family).count,
          total_count: family.accounts.count
        }
      }
    end

    # Find securities with stale prices
    def stale_securities(family)
      return Security.none unless family.trades.any?

      threshold = FRESHNESS_THRESHOLDS[:securities][:fresh].ago
      traded_securities(family).where("securities.updated_at < ? OR securities.updated_at IS NULL", threshold)
    end

    # Find stale exchange rates
    def stale_exchange_rates(family)
      return ExchangeRate.none unless family.requires_exchange_rates_data_provider?

      threshold = FRESHNESS_THRESHOLDS[:exchange_rates][:fresh].ago
      needed_exchange_rates(family).where("updated_at < ? OR updated_at IS NULL", threshold)
    end

    # Find stale holdings
    def stale_holdings(family)
      threshold = FRESHNESS_THRESHOLDS[:holdings][:fresh].ago
      family.holdings.where("date < ?", threshold.to_date)
    end

    # Find accounts with stale balances
    def stale_accounts(family)
      threshold = FRESHNESS_THRESHOLDS[:account_balances][:fresh].ago
      family.accounts.where("latest_sync_completed_at < ? OR latest_sync_completed_at IS NULL", threshold)
    end

    private

    def security_fresh?(security)
      return false if security.updated_at.nil?

      threshold = FRESHNESS_THRESHOLDS[:securities][:fresh]
      security.updated_at > threshold.ago
    end

    def exchange_rate_fresh?(rate)
      return false if rate.updated_at.nil?

      threshold = FRESHNESS_THRESHOLDS[:exchange_rates][:fresh]
      rate.updated_at > threshold.ago
    end

    def holding_fresh?(holding)
      threshold = FRESHNESS_THRESHOLDS[:holdings][:fresh]
      holding.date >= threshold.to_date
    end

    def balance_fresh?(balance)
      return false if balance.updated_at.nil?

      threshold = FRESHNESS_THRESHOLDS[:account_balances][:fresh]
      balance.updated_at > threshold.ago
    end

    def account_fresh?(account)
      return false if account.latest_sync_completed_at.nil?

      threshold = FRESHNESS_THRESHOLDS[:account_balances][:fresh]
      account.latest_sync_completed_at > threshold.ago
    end

    def calculate_age(record)
      last_updated = last_updated_for(record)
      return nil if last_updated.nil?

      Time.current - last_updated
    end

    def last_updated_for(record)
      case record.class.name
      when "Security", "ExchangeRate", "Balance"
        record.updated_at
      when "Holding"
        record.date.to_time if record.date.present?
      when "Account"
        record.latest_sync_completed_at
      else
        record.updated_at
      end
    end

    def thresholds_for(record)
      key = case record.class.name
            when "Security" then :securities
            when "ExchangeRate" then :exchange_rates
            when "Holding" then :holdings
            when "Balance", "Account" then :account_balances
            else :account_balances
            end

      FRESHNESS_THRESHOLDS[key]
    end

    def freshness_threshold_for(class_name)
      key = case class_name
            when "Security" then :securities
            when "ExchangeRate" then :exchange_rates
            when "Holding" then :holdings
            when "Balance", "Account" then :account_balances
            else :account_balances
            end

      FRESHNESS_THRESHOLDS[key]
    end

    def traded_securities(family)
      security_ids = family.trades.joins(:security).distinct.pluck("securities.id")
      Security.where(id: security_ids)
    end

    def needed_exchange_rates(family)
      currencies = family.enabled_currency_codes - [family.primary_currency_code]
      ExchangeRate.where(from_currency: currencies, to_currency: family.primary_currency_code)
    end

    def securities_freshness_score(family)
      return 100 unless family.trades.any?

      freshness_score(traded_securities(family))
    end

    def exchange_rates_freshness_score(family)
      return 100 unless family.requires_exchange_rates_data_provider?

      freshness_score(needed_exchange_rates(family))
    end

    def holdings_freshness_score(family)
      freshness_score(family.holdings)
    end

    def accounts_freshness_score(family)
      freshness_score(family.accounts)
    end
  end
end

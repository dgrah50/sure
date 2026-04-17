module DataHealth
  class ConfidenceScorer
    # Weight factors for confidence scoring
    WEIGHTS = {
      source: 0.50,      # 50% - Quality of data source
      recency: 0.30,     # 30% - How recent the data is
      verification: 0.20 # 20% - Verification status
    }.freeze

    # Source scores (higher = more reliable)
    SOURCE_SCORES = {
      live: 100,           # Real-time provider data
      manual_recent: 90,   # User-entered within 30 days
      calculated: 70,      # Derived from trades/calculations
      manual_stale: 50,    # User-entered > 30 days ago
      provider: 80,        # Provider-supplied data
      unknown: 0           # No confidence assessment
    }.freeze

    # Account provider reliability scores
    PROVIDER_SCORES = {
      plaid: 95,
      simplefin: 90,
      coinbase: 90,
      binance: 90,
      snaptrade: 85,
      coinstats: 80,
      manual: 70,
      unknown: 50
    }.freeze

    # Maximum age thresholds for freshness
    FRESHNESS_THRESHOLDS = {
      securities: 1.day,
      exchange_rates: 1.day,
      holdings: 7.days,
      account_balances: 1.day
    }.freeze

    def score_holding(holding)
      source_score = score_holding_source(holding)
      recency_score = score_holding_recency(holding)
      verification_score = score_holding_verification(holding)

      weighted_score(
        source: source_score,
        recency: recency_score,
        verification: verification_score
      )
    end

    def score_account(account)
      source_score = score_account_source(account)
      recency_score = score_account_recency(account)
      verification_score = score_account_verification(account)

      weighted_score(
        source: source_score,
        recency: recency_score,
        verification: verification_score
      )
    end

    def score_family(family)
      return 100 if family.accounts.none?

      total_score = 0
      count = 0

      family.accounts.find_each do |account|
        total_score += score_account(account)
        count += 1
      end

      return 100 if count == 0

      (total_score.to_f / count).round
    end

    def explain_holding(holding)
      {
        overall: score_holding(holding),
        breakdown: {
          source: {
            score: score_holding_source(holding),
            weight: WEIGHTS[:source],
            details: source_details(holding)
          },
          recency: {
            score: score_holding_recency(holding),
            weight: WEIGHTS[:recency],
            details: recency_details(holding)
          },
          verification: {
            score: score_holding_verification(holding),
            weight: WEIGHTS[:verification],
            details: verification_details(holding)
          }
        }
      }
    end

    private

    def weighted_score(source:, recency:, verification:)
      score = (
        source * WEIGHTS[:source] +
        recency * WEIGHTS[:recency] +
        verification * WEIGHTS[:verification]
      ).round

      [score, 100].min
    end

    def score_holding_source(holding)
      confidence_key = holding.confidence&.to_sym || :unknown
      SOURCE_SCORES[confidence_key] || SOURCE_SCORES[:unknown]
    end

    def score_holding_recency(holding)
      return 100 if holding.recently_verified?
      return 70 if holding.date > 7.days.ago
      return 40 if holding.date > 30.days.ago
      20
    end

    def score_holding_verification(holding)
      score = 0
      score += 50 if holding.cost_basis_known?
      score += 50 if holding.recently_verified?
      score
    end

    def score_account_source(account)
      provider_key = account.source&.to_sym || :unknown
      PROVIDER_SCORES[provider_key] || PROVIDER_SCORES[:unknown]
    end

    def score_account_recency(account)
      return 100 if account.latest_sync_completed_at.present? && account.latest_sync_completed_at > 1.day.ago
      return 70 if account.latest_sync_completed_at.present? && account.latest_sync_completed_at > 7.days.ago
      return 40 if account.latest_sync_completed_at.present? && account.latest_sync_completed_at > 30.days.ago
      0
    end

    def score_account_verification(account)
      return 100 if account.syncs.successful.any?
      50
    end

    def source_details(holding)
      confidence = holding.confidence || "unknown"
      {
        confidence_level: confidence,
        confidence_label: holding.confidence_label,
        cost_basis_source: holding.cost_basis_source,
        cost_basis_locked: holding.cost_basis_locked?
      }
    end

    def recency_details(holding)
      {
        holding_date: holding.date,
        last_verified_at: holding.last_verified_at,
        days_since_verification: holding.last_verified_at ? (Date.current - holding.last_verified_at.to_date).to_i : nil,
        is_recent: holding.recently_verified?
      }
    end

    def verification_details(holding)
      {
        cost_basis_known: holding.cost_basis_known?,
        cost_basis: holding.cost_basis,
        avg_cost_present: holding.avg_cost.present?,
        security_verified: holding.security_locked?
      }
    end
  end
end

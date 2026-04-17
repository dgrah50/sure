class InstrumentMappingSuggestionJob < ApplicationJob
  queue_as :default

  # Pattern matching rules for suggesting sleeve mappings
  SLEEVE_PATTERNS = {
    # US Equities
    /\b(SPY|VTI|VOO|IVV|QQQ|VTI|VXUS)\b/i => "US Equities",
    /\b(AAPL|MSFT|AMZN|GOOGL|GOOG|TSLA|NVDA|META|NFLX)\b/i => "US Equities",

    # International Equities
    /\b(VEA|VWO|EFA|IEFA|VXUS|VSS)\b/i => "International Equities",

    # Bonds/Fixed Income
    /\b(AGG|BND|TLT|IEF|LQD|VCIT|VGIT|BNDX)\b/i => "Bonds",
    /\b(TREASURY|BOND|FIXED.INCOME)\b/i => "Bonds",

    # Real Estate
    /\b(VNQ|VNQI|SCHH|REET)\b/i => "Real Estate",
    /\b(REIT|REAL.ESTATE)\b/i => "Real Estate",

    # Commodities
    /\b(GLD|SLV|IAU|PALL|PPLT|GSG|DBC)\b/i => "Commodities",
    /\b(GOLD|SILVER|COMMODITY)\b/i => "Commodities",

    # Crypto
    /\b(BTC|ETH|BTCUSD|ETHUSD|SOLUSD|ADAUSD)\b/i => "Crypto",
    /\b(BITCOIN|ETHEREUM|CRYPTO)\b/i => "Crypto",

    # Cash/Money Market
    /\b(VMFXX|SPAXX|FDRXX|SWVXX)\b/i => "Cash",
    /\b(MONEY.MARKET|CASH|MMF)\b/i => "Cash"
  }.freeze

  def perform(family_id = nil)
    families = family_id.present? ? Family.where(id: family_id) : Family.all

    families.find_each do |family|
      suggest_mappings_for_family(family)
    end
  end

  private

    def suggest_mappings_for_family(family)
      holdings = family.holdings
        .includes(:security, :account, :instrument_mapping)
        .where(instrument_mappings: { id: nil })
        .where.not(security: nil)

      holdings.find_each do |holding|
        suggest_mapping_for_holding(holding, family)
      end
    end

    def suggest_mapping_for_holding(holding, family)
      security = holding.security
      return unless security

      # Try to find a matching sleeve based on patterns
      suggested_sleeve = find_suggested_sleeve(security, family)

      if suggested_sleeve.present?
        confidence = calculate_confidence(security, suggested_sleeve)

        InstrumentMapping.create!(
          holding: holding,
          sleeve: suggested_sleeve,
          mapped_status: :pending,
          mapping_confidence: confidence,
          suggested_by: "pattern_match",
          suggestion_details: {
            pattern_matched: find_matching_pattern(security),
            security_name: security.name,
            ticker: security.ticker
          }
        )
      else
        # Create a pending mapping with no suggested sleeve
        InstrumentMapping.create!(
          holding: holding,
          mapped_status: :pending,
          mapping_confidence: :low,
          suggested_by: "no_match",
          suggestion_details: {
            security_name: security.name,
            ticker: security.ticker
          }
        )
      end
    rescue => e
      Rails.logger.error("Failed to suggest mapping for holding #{holding.id}: #{e.message}")
    end

    def find_suggested_sleeve(security, family)
      return nil unless security.respond_to?(:ticker) && security.ticker.present?

      # Find matching pattern
      suggested_sleeve_name = nil
      SLEEVE_PATTERNS.each do |pattern, sleeve_name|
        if security.ticker =~ pattern
          suggested_sleeve_name = sleeve_name
          break
        end
      end

      return nil unless suggested_sleeve_name

      # Find the sleeve in the family's active policy
      find_sleeve_by_name(suggested_sleeve_name, family)
    end

    def find_sleeve_by_name(name, family)
      return nil unless family.respond_to?(:policy_versions)

      current_policy = family.policy_versions.active.first
      return nil unless current_policy

      current_policy.sleeves.find_by("name ILIKE ?", "%#{name}%")
    end

    def calculate_confidence(security, sleeve)
      # Higher confidence for exact ticker matches vs pattern matches
      ticker = security.ticker.to_s.upcase

      if %w[SPY VTI VOO IVV QQQ VXUS AGG BND VNQ GLD BTC ETH].include?(ticker)
        :high
      elsif ticker.match?(/\b(AAPL|MSFT|AMZN|GOOGL|TSLA|NVDA)\b/i)
        :high
      else
        :medium
      end
    end

    def find_matching_pattern(security)
      return nil unless security.respond_to?(:ticker) && security.ticker.present?

      SLEEVE_PATTERNS.each do |pattern, sleeve_name|
        return { pattern: pattern.source, sleeve: sleeve_name } if security.ticker =~ pattern
      end

      nil
    end
end

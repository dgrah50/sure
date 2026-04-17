class DataQualitySummary < ApplicationRecord
  belongs_to :family

  validates :family_id, uniqueness: true
  validates :overall_score, :price_freshness_score, :fx_freshness_score, :holdings_quality_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def self.refresh!(family)
    summary = find_or_initialize_by(family: family)
    summary.calculate_and_save!
    summary
  end

  def calculate_and_save!
    self.price_freshness_score = calculate_price_freshness_score
    self.fx_freshness_score = calculate_fx_freshness_score
    self.holdings_quality_score = calculate_holdings_quality_score
    self.overall_score = calculate_overall_score
    self.last_sync_at = Time.current
    self.breakdown = build_breakdown

    save!
  end

  def health_status
    case overall_score
    when 90..100 then "excellent"
    when 75...90 then "good"
    when 60...75 then "fair"
    when 40...60 then "poor"
    else "critical"
    end
  end

  def excellent?
    overall_score >= 90
  end

  def good?
    overall_score >= 75 && overall_score < 90
  end

  def fair?
    overall_score >= 60 && overall_score < 75
  end

  def poor?
    overall_score >= 40 && overall_score < 60
  end

  def critical?
    overall_score < 40
  end

  def any_issues?
    overall_score < 100
  end

  private

  def calculate_price_freshness_score
    return 100 if family.trades.none?

    freshness_checker = DataHealth::DataFreshness.new
    stale_count = 0
    total_count = 0

    family.trades.joins(:security).distinct.pluck("securities.id").each do |security_id|
      security = Security.find(security_id)
      total_count += 1
      stale_count += 1 unless freshness_checker.fresh?(security)
    end

    return 100 if total_count == 0

    ((total_count - stale_count).to_f / total_count * 100).round
  end

  def calculate_fx_freshness_score
    return 100 unless family.requires_exchange_rates_data_provider?

    freshness_checker = DataHealth::DataFreshness.new
    stale_count = 0
    total_count = 0

    family.enabled_currency_codes.each do |currency_code|
      next if currency_code == family.primary_currency_code

      total_count += 1
      rate = ExchangeRate.find_by(from_currency: currency_code, to_currency: family.primary_currency_code)
      stale_count += 1 if rate.nil? || !freshness_checker.fresh?(rate)
    end

    return 100 if total_count == 0

    ((total_count - stale_count).to_f / total_count * 100).round
  end

  def calculate_holdings_quality_score
    return 100 if family.holdings.none?

    scorer = DataHealth::ConfidenceScorer.new
    total_score = 0
    count = 0

    family.holdings.includes(:security, :account).find_each do |holding|
      total_score += scorer.score_holding(holding)
      count += 1
    end

    return 100 if count == 0

    (total_score.to_f / count).round
  end

  def calculate_overall_score
    weights = {
      price_freshness_score => 0.35,
      fx_freshness_score => 0.25,
      holdings_quality_score => 0.40
    }

    weighted_sum = weights.sum { |score, weight| score * weight }
    weighted_sum.round
  end

  def build_breakdown
    {
      price_freshness: {
        score: price_freshness_score,
        status: score_to_status(price_freshness_score),
        description: "Percentage of securities with fresh price data"
      },
      fx_freshness: {
        score: fx_freshness_score,
        status: score_to_status(fx_freshness_score),
        description: "Percentage of currency pairs with fresh exchange rates"
      },
      holdings_quality: {
        score: holdings_quality_score,
        status: score_to_status(holdings_quality_score),
        description: "Average confidence score of all holdings"
      },
      overall: {
        score: overall_score,
        status: health_status,
        description: "Weighted composite of all data quality dimensions"
      },
      calculated_at: Time.current.iso8601
    }
  end

  def score_to_status(score)
    case score
    when 90..100 then "pass"
    when 75...90 then "warning"
    else "fail"
    end
  end
end

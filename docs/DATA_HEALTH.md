# Data Health System

The Data Health System provides comprehensive data quality monitoring, confidence scoring, and remediation guidance for portfolio data.

## Overview

Data quality is critical for accurate portfolio analysis. This system continuously monitors:

- **Price freshness** - How current security prices are
- **FX rate freshness** - How current exchange rates are
- **Holdings quality** - Confidence in holding data accuracy
- **Account sync status** - Whether accounts are successfully syncing
- **Data completeness** - Missing cost basis, orphaned transactions, etc.

## Data Quality Dimensions

### 1. Price Freshness

Security prices are checked against freshness thresholds:

| Status | Age | Action |
|--------|-----|--------|
| Fresh | < 1 day | None |
| Warning | 1-3 days | Monitor |
| Stale | 3-7 days | Alert |
| Critical | > 7 days | Urgent action |

### 2. FX Rate Freshness

Exchange rates follow the same thresholds as prices (1/3/7 days).

### 3. Holdings Quality

Holdings are scored on three dimensions:

| Dimension | Weight | Description |
|-----------|--------|-------------|
| Source | 50% | Quality of data provider |
| Recency | 30% | How recently data was updated |
| Verification | 20% | Whether cost basis is known and verified |

### 4. Account Sync Status

Tracks whether accounts successfully sync:
- Last successful sync timestamp
- Provider connection health
- Authentication status

## Confidence Scoring Algorithm

The `DataHealth::ConfidenceScorer` computes weighted confidence scores:

```
Overall Score = (Source × 0.50) + (Recency × 0.30) + (Verification × 0.20)
```

### Source Scores

| Source | Score | Description |
|--------|-------|-------------|
| Live | 100 | Real-time provider data |
| Manual (Recent) | 90 | User-entered within 30 days |
| Provider | 80 | Provider-supplied data |
| Calculated | 70 | Derived from trades |
| Manual (Stale) | 50 | User-entered > 30 days ago |
| Unknown | 0 | No confidence assessment |

### Provider Reliability Scores

| Provider | Score |
|----------|-------|
| Plaid | 95 |
| SimpleFIN | 90 |
| Coinbase | 90 |
| Binance | 90 |
| Snaptrade | 85 |
| CoinStats | 80 |
| Manual | 70 |
| Unknown | 50 |

## Data Quality Checks

The system performs the following check types:

### `price_stale`
Security prices that haven't been updated within the freshness threshold.

**Remediation:** Trigger a manual sync or check provider connection.

### `fx_stale`
Exchange rates that haven't been updated within the freshness threshold.

**Remediation:** Check exchange rate provider configuration.

### `holding_missing_basis`
Holdings without cost basis information.

**Remediation:**
- Check if provider supplies cost basis
- Manually enter cost basis for the holding
- Lock cost basis once verified

### `account_sync_failed`
Accounts that failed their last sync attempt.

**Remediation:**
- Check provider credentials
- Re-authenticate if necessary
- Check provider status page

### `security_missing_classification`
Securities without proper classification (missing sector, asset type, etc.).

**Remediation:** Update security metadata or remap to a different security.

### `duplicate_holding`
Multiple holdings for the same security on the same date.

**Remediation:** Merge or delete duplicate holdings.

### `orphaned_transaction`
Transactions not linked to any account or holding.

**Remediation:** Reconcile transactions or delete if erroneous.

## Health Status Levels

The overall data quality score maps to health status:

| Score Range | Status | Description |
|-------------|--------|-------------|
| 90-100 | Excellent | Data is fresh and complete |
| 75-89 | Good | Minor issues, data is usable |
| 60-74 | Fair | Some issues require attention |
| 40-59 | Poor | Significant data quality issues |
| 0-39 | Critical | Data may be unreliable |

## Usage Examples

### Check Data Quality Summary

```ruby
# Refresh and get current summary
summary = DataQualitySummary.refresh!(family)
summary.overall_score  # => 87
summary.health_status  # => "good"
```

### Record a Data Quality Check

```ruby
DataQualityCheck.record_check!(
  family: family,
  check_type: "price_stale",
  status: "warning",
  details: { security_id: 123, ticker: "AAPL", last_updated: 2.days.ago }
)
```

### Check Freshness

```ruby
freshness = DataHealth::DataFreshness.new
freshness.fresh?(security)  # => true/false
freshness.status(holding)   # => :fresh/:warning/:stale/:critical

# Get family-wide summary
summary = freshness.family_summary(family)
```

### Score Confidence

```ruby
scorer = DataHealth::ConfidenceScorer.new
scorer.score_holding(holding)   # => 0-100
scorer.score_account(account)   # => 0-100
scorer.score_family(family)     # => 0-100

# Get detailed breakdown
scorer.explain_holding(holding)
# => {
#   overall: 85,
#   breakdown: {
#     source: { score: 100, weight: 0.50, ... },
#     recency: { score: 70, weight: 0.30, ... },
#     verification: { score: 100, weight: 0.20, ... }
#   }
# }
```

### Find Stale Data

```ruby
freshness = DataHealth::DataFreshness.new
freshness.stale_securities(family)
freshness.stale_exchange_rates(family)
freshness.stale_holdings(family)
freshness.stale_accounts(family)
```

## Database Schema

### data_quality_checks

| Column | Type | Description |
|--------|------|-------------|
| family_id | bigint | Reference to family |
| check_type | string | Type of check (price_stale, fx_stale, etc.) |
| status | string | pass/warning/fail |
| details | jsonb | Additional context |
| checked_at | datetime | When check was performed |
| resolved_at | datetime | When issue was resolved |

### data_quality_summaries

| Column | Type | Description |
|--------|------|-------------|
| family_id | bigint | Reference to family (unique) |
| overall_score | integer | 0-100 composite score |
| price_freshness_score | integer | 0-100 |
| fx_freshness_score | integer | 0-100 |
| holdings_quality_score | integer | 0-100 |
| last_sync_at | datetime | When summary was last calculated |
| breakdown | jsonb | Detailed score breakdown |

## Background Processing

Data quality checks should be run:
1. After each account sync completes
2. Daily via scheduled job
3. On-demand when user requests data health report

## Future Enhancements

- Trend analysis over time
- Predictive data quality alerts
- Automated remediation suggestions
- Integration with notification system
- Portfolio impact analysis for data quality issues

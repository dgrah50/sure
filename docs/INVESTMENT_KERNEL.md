# Investment Kernel

The investment kernel is the core domain model powering the Portfolio Operating System. It provides the foundational infrastructure for tracking multi-account portfolios, managing security prices, calculating holdings valuations, handling cost basis tracking, and integrating with external financial data providers.

## Table of Contents

- [Overview](#overview)
- [Account Types and Delegated Type System](#account-types-and-delegated-type-system)
- [Holdings with Cost Basis and Source Tracking](#holdings-with-cost-basis-and-source-tracking)
- [Security Model and Price Providers](#security-model-and-price-providers)
- [Trade Model and Activity Labels](#trade-model-and-activity-labels)
- [Balance Tracking (Cash vs Non-Cash)](#balance-tracking-cash-vs-non-cash)
- [Valuation Model for Manual Accounts](#valuation-model-for-manual-accounts)
- [Sync Infrastructure](#sync-infrastructure)
- [Provider Integration Architecture](#provider-integration-architecture)

---

## Overview

The investment kernel handles:

- **Multi-account portfolio tracking** across diverse asset classes and account types
- **Security price discovery and caching** with multiple provider fallbacks
- **Holdings valuation and cost basis tracking** with manual and provider-sourced data
- **Multi-currency support** with exchange rate management
- **Sync infrastructure** for linked accounts and external data sources
- **Provider abstraction** enabling integration with banks, brokerages, and market data services

### Key Design Principles

1. **Delegated Type Pattern**: Uses Rails delegated types for polymorphic account behavior without complex STI inheritance
2. **Source-Aware Cost Basis**: Tracks where cost basis data originates (manual, calculated, provider) with priority-based conflict resolution
3. **Provider Abstraction**: Clean adapter pattern for external integrations with consistent interfaces
4. **Dual Calculator Strategy**: Forward calculator for manual accounts, reverse calculator for linked accounts

---

## Account Types and Delegated Type System

### Core Account Model

**Location**: `app/models/account.rb`

The `Account` model uses Rails' delegated type system to provide polymorphic behavior without single-table inheritance. Each account delegates its accountable behavior to a specific type model.

```ruby
class Account < ApplicationRecord
  delegated_type :accountable, types: Accountable::TYPES
  
  # State machine via AASM
  include AASM
  aasm column: :status do
    state :active, initial: true
    state :draft, :disabled, :pending_deletion
    # ... transitions
  end
end
```

**Key Attributes**:
- `accountable_type` - The delegated type (Investment, Depository, etc.)
- `classification` - `:asset` or `:liability`
- `balance_type` - `:cash`, `:non_cash`, or `:investment`

### Account Types

**Location**: `app/models/accountable.rb`

The `Accountable` module defines the complete list of supported account types:

| Category | Types |
|----------|-------|
| **Cash** | `Depository` (checking, savings, money market) |
| **Investments** | `Investment` (brokerage, retirement, etc.) |
| **Crypto** | `Crypto` (cryptocurrency holdings) |
| **Manual Assets** | `Property`, `Vehicle`, `OtherAsset` |
| **Liabilities** | `CreditCard`, `Loan`, `OtherLiability` |

### Investment Account Subtypes

**Location**: `app/models/investment.rb`

The `Investment` model defines region-specific account subtypes with appropriate tax treatments:

**United States**:
```ruby
brokerage, 401k, roth_401k, 403b, 457b, tsp, ira, roth_ira, 
sep_ira, simple_ira, 529_plan, hsa, ugma, utma
```

**United Kingdom**:
```ruby
isa, lisa, sipp, workplace_pension_uk
```

**Canada**:
```ruby
tfsa, rrsp, non_registered, fhsa, rdsp, resp, dpsp, prpp, 
lira, rrif, lif, lrif, prif, rlif
```

**Australia**:
```ruby
super, smsf
```

**Europe**:
```ruby
pea, pillar_3a, riester
```

**Generic**:
```ruby
pension, retirement, mutual_fund, angel, trust, other
```

### Tax Treatments

Each investment subtype has a `tax_treatment`:

| Treatment | Description |
|-----------|-------------|
| `taxable` | Standard taxable account (e.g., brokerage) |
| `tax_deferred` | Pre-tax contributions, taxed on withdrawal (e.g., traditional 401k, IRA) |
| `tax_exempt` | No tax on growth or qualified withdrawals (e.g., Roth IRA, HSA) |
| `tax_advantaged` | Region-specific tax benefits (e.g., UK ISA) |

---

## Holdings with Cost Basis and Source Tracking

### Holding Model

**Location**: `app/models/holding.rb`

A `Holding` represents a position snapshot at a specific point in time:

```ruby
class Holding < ApplicationRecord
  belongs_to :account
  belongs_to :security
  
  # Core position data
  attribute :qty          # Quantity held (shares/units)
  attribute :price        # Price per unit
  attribute :amount       # qty * price (total market value)
  attribute :currency     # Currency code
  attribute :date         # Snapshot date
  
  # Cost basis tracking
  attribute :cost_basis           # Average cost per unit
  attribute :cost_basis_source    # Enum: manual, calculated, provider
  attribute :cost_basis_locked    # Prevent provider overwrite
  
  # Provider linkage
  attribute :external_id          # Provider's holding ID
  attribute :account_provider_id  # Linked AccountProvider
  attribute :provider_security_id # For security remapping
  attribute :security_locked      # Prevent provider security changes
end
```

### Cost Basis Source Priority

The kernel uses a priority system for cost basis data:

| Source | Priority | Description |
|--------|----------|-------------|
| `manual` | 3 (highest) | User-entered cost basis, never overwritten |
| `calculated` | 2 | Computed from trade history |
| `provider` | 1 | From linked account provider |
| `nil` | 0 (lowest) | No cost basis known |

Higher priority sources cannot be overwritten by lower priority sources unless explicitly unlocked.

### Key Holding Methods

**Valuation Methods**:
```ruby
# Average cost per share
holding.avg_cost  # => Money

# Unrealized gain/loss
holding.trend  # => Money (current value - cost basis total)

# Day-over-day change
holding.day_change  # => Money

# Portfolio weight percentage
holding.weight(portfolio_total)  # => Percentage
```

**Cost Basis Management**:
```ruby
# Check if new cost basis can replace current
holding.cost_basis_replaceable_by?(new_source)  # => boolean

# User sets manual cost basis (locks it)
holding.set_manual_cost_basis!(amount)

# Unlock for provider updates
holding.unlock_cost_basis!
```

**Security Remapping** (for correcting ticker mismatches):
```ruby
# Remap to different security
holding.remap_security!(new_security)

# Reset to provider's security
holding.reset_security_to_provider!
```

### Holding Materializer

**Location**: `app/models/holding/materializer.rb`

The materializer calculates holdings from either trades or provider snapshots, depending on account type.

```ruby
class Holding::Materializer
  def initialize(account)
    @account = account
  end
  
  def materialize
    if account.linked?
      ReverseCalculator.new(account).calculate
    else
      ForwardCalculator.new(account).calculate
    end
  end
end
```

### Forward Calculator

**Location**: `app/models/holding/forward_calculator.rb`

For **manual accounts**, builds the portfolio forward from trade history:

1. Start with empty positions
2. Iterate through trades chronologically
3. Calculate running quantities and cost basis
4. Apply buy/sell logic for average cost tracking

Best for: Manual accounts where trades are entered by the user.

### Reverse Calculator

**Location**: `app/models/holding/reverse_calculator.rb`

For **linked accounts**, works backward from the provider's current snapshot:

1. Start with provider's current holdings
2. Work backward through trades
3. Reconstruct historical positions
4. Preserves provider's current cost basis

Best for: Linked accounts where the provider is the source of truth for current positions.

---

## Security Model and Price Providers

### Security Model

**Location**: `app/models/security.rb`

A `Security` represents a tradable asset (stock, ETF, mutual fund, cryptocurrency):

```ruby
class Security < ApplicationRecord
  attribute :ticker              # Trading symbol (AAPL, BTC-USD)
  attribute :name                # Display name
  attribute :logo_url            # Company/asset logo
  attribute :exchange_operating_mic  # Market identifier code
  attribute :price_provider      # Preferred price provider
  attribute :kind                # "standard" or "cash"
  attribute :offline             # Provider unavailable flag
  attribute :offline_reason      # Explanation for unavailability
  attribute :first_provider_price_on  # Earliest available price
end
```

### Security Identification

**Cryptocurrency Detection**:
```ruby
security.crypto?  # => true if exchange_operating_mic == "BINANCE"
security.crypto_base_asset  # => "BTC" for "BTC-USD"
```

**MIC Codes**: Market Identifier Codes (ISO 10383) identify exchanges:
- `XNAS` - NASDAQ
- `XNYS` - New York Stock Exchange
- `BINANCE` - Binance (crypto)
- `ARCX` - NYSE Arca

### Price Providers

**Location**: `app/models/provider/registry.rb`

The kernel integrates with multiple price providers for redundancy:

| Provider | Asset Classes | Notes |
|----------|---------------|-------|
| `twelve_data` | Stocks, ETFs | Global coverage |
| `yahoo_finance` | Stocks, ETFs, Crypto | Free tier available |
| `tiingo` | Stocks, ETFs, Mutual Funds | US-focused |
| `eodhd` | Stocks, ETFs, Crypto | End-of-day pricing |
| `alpha_vantage` | Stocks, Forex | API limits |
| `mfapi` | Mutual Funds | Indian mutual funds |
| `binance_public` | Crypto | Cryptocurrency prices |

**Provider Selection**:
```ruby
security.price_provider  # Preferred provider for this security
Provider::Registry.get(:securities, provider_name)  # Get provider instance
```

### Security Price Model

**Location**: `app/models/security/price.rb`

Stores historical and current prices:

```ruby
class Security::Price < ApplicationRecord
  belongs_to :security
  
  attribute :date         # Price date
  attribute :price        # Price value
  attribute :currency     # Price currency
  attribute :provisional  # Gap-filled/estimated price
end
```

**Price Fetching**:
```ruby
# Get latest price (lazy fetch if not cached)
security.current_price  # => Security::Price

# Get historical price
Security::Price.find_price(security, date)  # => Security::Price
```

**Provisional Prices**: When a price is missing for a date, the system may create a provisional price using forward-fill from the last known price. These are marked as `provisional: true` and refreshed on the next sync.

---

## Trade Model and Activity Labels

### Trade Model

**Location**: `app/models/trade.rb`

A `Trade` represents a transaction that affects holdings:

```ruby
class Trade < ApplicationRecord
  belongs_to :account
  belongs_to :security, optional: true  # nil for cash-only transactions
  
  attribute :qty          # Positive = buy, Negative = sell
  attribute :price        # Execution price per unit
  attribute :currency     # Trade currency
  attribute :fee          # Transaction fees
  attribute :investment_activity_label  # Activity classification
  attribute :traded_at    # Execution timestamp
end
```

### Activity Labels

Trades are classified by activity type for reporting and analysis:

| Label | Direction | Description |
|-------|-----------|-------------|
| `Buy` | In | Purchase securities |
| `Sell` | Out | Sell securities |
| `Sweep In` | In | Cash sweep into investment account |
| `Sweep Out` | Out | Cash sweep out of investment account |
| `Dividend` | In | Dividend payment |
| `Reinvestment` | In | Dividend reinvestment (DRIP) |
| `Interest` | In | Interest earned |
| `Fee` | Out | Account/transaction fees |
| `Transfer` | Both | Transfer between accounts |
| `Contribution` | In | Retirement account contribution |
| `Withdrawal` | Out | Retirement account withdrawal |
| `Exchange` | Both | Fund exchange within provider |
| `Other` | Both | Uncategorized activity |

### Key Trade Methods

**Trade Type Checks**:
```ruby
trade.buy?   # => qty > 0
trade.sell?  # => qty < 0
```

**Gain/Loss Calculations**:
```ruby
# For buy trades: unrealized P&L based on current price
trade.unrealized_gain_loss(current_price)  # => Money

# For sell trades: realized P&L at time of sale
trade.realized_gain_loss  # => Money (requires cost_basis)
```

---

## Balance Tracking (Cash vs Non-Cash)

### Balance Model

**Location**: `app/models/balance.rb`

Daily balance snapshots with detailed cash flow tracking:

```ruby
class Balance < ApplicationRecord
  belongs_to :account
  
  # Snapshot data
  attribute :date              # Snapshot date
  attribute :balance           # Total balance
  attribute :cash_balance      # Cash portion
  attribute :currency          # Currency code
  
  # Period tracking (for flows)
  attribute :start_cash_balance
  attribute :start_non_cash_balance
  
  # Cash flows
  attribute :cash_inflows      # Deposits, dividends, interest
  attribute :cash_outflows     # Withdrawals, fees
  attribute :cash_adjustments  # Corrections
  
  # Non-cash flows
  attribute :non_cash_inflows
  attribute :non_cash_outflows
  attribute :non_cash_adjustments
  
  # Market effects
  attribute :net_market_flows  # Appreciation/depreciation
  
  # Ending balances
  attribute :end_cash_balance
  attribute :end_non_cash_balance
  attribute :end_balance
end
```

### Balance Types by Account

| Account Type | Balance Type | Cash Balance | Non-Cash Balance |
|--------------|--------------|--------------|------------------|
| `Depository` | Cash | Full balance | Zero |
| `CreditCard` | Cash | Full balance (negative) | Zero |
| `Investment` | Investment | Cash sweep/money market | Holdings value |
| `Crypto` | Investment | Cash/fiat | Crypto holdings |
| `Property` | Non-cash | Zero | Property value |
| `Vehicle` | Non-cash | Zero | Vehicle value |
| `Loan` | Non-cash | Zero | Loan balance (negative) |

### Balance Materializer

**Location**: `app/models/balance/materializer.rb`

Orchestrates the balance calculation pipeline:

```ruby
class Balance::Materializer
  def initialize(account, date_range)
    @account = account
    @date_range = date_range
  end
  
  def materialize
    # 1. Materialize holdings first
    Holding::Materializer.new(account).materialize(date_range)
    
    # 2. Calculate balances
    calculator = account.linked? ? 
      ReverseCalculator.new(account, date_range) :
      ForwardCalculator.new(account, date_range)
    
    calculator.calculate
  end
end
```

### Balance Calculators

**Forward Calculator** (`app/models/balance/forward_calculator.rb`):
- Used for manual accounts
- Starts from last known balance
- Applies trades and valuations forward
- Handles cash flow categorization

**Reverse Calculator** (`app/models/balance/reverse_calculator.rb`):
- Used for linked accounts
- Starts from provider's current balance
- Works backward through transactions
- Maintains provider's cash/money market categorization

---

## Valuation Model for Manual Accounts

### Valuation Model

**Location**: `app/models/valuation.rb`

For manual accounts without trade history, valuations provide balance points:

```ruby
class Valuation < ApplicationRecord
  belongs_to :account
  belongs_to :security, optional: true  # nil for account-level valuations
  
  enum kind: {
    reconciliation: 0,  # Manual balance adjustment
    opening_anchor: 1,  # Starting balance point
    current_anchor: 2   # Current balance point
  }
  
  attribute :value      # Valuation amount
  attribute :currency   # Currency code
  attribute :date       # Valuation date
end
```

### Valuation Kinds

| Kind | Use Case |
|------|----------|
| `reconciliation` | Periodic balance corrections (reconciling to statements) |
| `opening_anchor` | Initial balance when account is created |
| `current_anchor` | Current known balance (for accounts without sync) |

### Usage in Calculations

Valuations serve as anchor points in balance calculations:

1. **Opening Anchor**: Starting point for forward calculations
2. **Reconciliation**: Overrides calculated balance at specific dates
3. **Current Anchor**: Used when no other data is available

```ruby
# Example: Property account with annual valuations
account.valuations.create!(
  kind: :opening_anchor,
  value: 500_000,
  currency: "USD",
  date: "2020-01-01"
)

account.valuations.create!(
  kind: :reconciliation,
  value: 550_000,
  currency: "USD", 
  date: "2023-01-01"
)
```

---

## Sync Infrastructure

### Sync Model

**Location**: `app/models/sync.rb`

The `Sync` model tracks synchronization operations across the portfolio:

```ruby
class Sync < ApplicationRecord
  include AASM
  
  # State machine
  aasm column: :status do
    state :pending, initial: true
    state :syncing
    state :completed, :failed, :stale
  end
  
  # Polymorphic sync target
  belongs_to :syncable, polymorphic: true
  
  # Hierarchy for batch operations
  belongs_to :parent, class_name: "Sync", optional: true
  has_many :children, class_name: "Sync", foreign_key: :parent_id
  
  attribute :window_start_date  # Sync period start
  attribute :window_end_date    # Sync period end
  attribute :sync_stats         # Performance/result stats
  attribute :status_text        # Human-readable status
end
```

### Syncable Concern

**Location**: `app/models/concerns/syncable.rb`

Provides sync capabilities to models:

```ruby
module Syncable
  extend ActiveSupport::Concern
  
  def sync_later(start_date: nil, end_date: Date.current)
    sync = create_sync!(start_date, end_date)
    SyncJob.perform_later(sync)
    sync
  end
  
  def perform_sync
    # Override in including class
  end
  
  def perform_post_sync
    # Post-sync cleanup/notification
  end
  
  def syncing?
    syncs.where(status: [:pending, :syncing]).exists?
  end
end
```

**Syncable Models**:
- `Account` - Sync individual account
- `Family` - Sync all family accounts
- `PlaidItem` - Sync Plaid-connected accounts
- `SimplefinItem` - Sync SimpleFIN-connected accounts
- `LunchflowItem` - Sync Lunchflow-connected accounts
- And other provider item types

### Account Syncer

**Location**: `app/models/account/syncer.rb`

Coordinates the sync process for an account:

```ruby
class Account::Syncer
  def initialize(account, sync)
    @account = account
    @sync = sync
  end
  
  def sync
    # 1. Import market data (prices, exchange rates)
    import_market_data
    
    # 2. Sync holdings (forward or reverse)
    materialize_balances
    
    # 3. Run post-sync hooks
    account.perform_post_sync
  end
  
  private
  
  def import_market_data
    # Fetch exchange rates for account currency
    # Fetch security prices for holdings
  end
  
  def materialize_balances
    materializer = Balance::Materializer.new(account, date_range)
    materializer.materialize
  end
end
```

### Family Syncer

**Location**: `app/models/family/syncer.rb`

Batch syncs all syncable items in a family:

```ruby
class Family::Syncer
  SYNCABLE_ITEM_ASSOCIATIONS = [
    :plaid_items,
    :simplefin_items,
    :lunchflow_items,
    :enable_banking_items,
    :indexa_capital_items,
    :coinbase_items,
    :coinstats_items,
    :mercury_items,
    :snaptrade_items
  ]
  
  def sync_all
    SYNCABLE_ITEM_ASSOCIATIONS.each do |association|
      family.public_send(association).find_each(&:sync_later)
    end
  end
end
```

---

## Provider Integration Architecture

### Provider Base

**Location**: `app/models/provider/base.rb`

Abstract base class for all provider adapters:

```ruby
class Provider::Base
  # Identity
  def provider_name
    raise NotImplementedError
  end
  
  # Capabilities
  def supported_account_types
    []
  end
  
  def connection_configs
    {}
  end
  
  def can_delete_holdings?
    false
  end
  
  # Data fetching (override in subclasses)
  def fetch_holdings(account)
    []
  end
  
  def fetch_transactions(account, start_date: nil, end_date: nil)
    []
  end
  
  def fetch_balances(account)
    {}
  end
end
```

### Provider Factory

**Location**: `app/models/provider/factory.rb`

Registry pattern for provider instantiation:

```ruby
class Provider::Factory
  REGISTRY = {
    plaid: Provider::Plaid,
    simplefin: Provider::Simplefin,
    # ... additional providers
  }
  
  def self.build(provider_name, credentials = {})
    provider_class = REGISTRY[provider_name.to_sym]
    provider_class.new(credentials)
  end
end
```

### Provider Registry

**Location**: `app/models/provider/registry.rb`

Manages provider discovery for different service types:

```ruby
class Provider::Registry
  CONCEPTS = %i[exchange_rates securities llm]
  
  def self.get(concept, provider_name)
    # Return appropriate provider for service type
  end
  
  def self.available_for(concept)
    # List available providers for concept
  end
end
```

### Account Provider

**Location**: `app/models/account_provider.rb`

Links accounts to their external provider representation:

```ruby
class AccountProvider < ApplicationRecord
  belongs_to :account
  belongs_to :provider_item, polymorphic: true  # PlaidItem, SimplefinItem, etc.
  
  attribute :external_id      # Provider's account ID
  attribute :external_name    # Provider's account name
  attribute :external_type    # Provider's account type
  attribute :external_subtype # Provider's subtype
  attribute :external_mask    # Account number mask
end
```

### Example: Plaid Integration

**Location**: `app/models/provider/plaid.rb`, `app/models/plaid_item/syncer.rb`

```ruby
class Provider::Plaid < Provider::Base
  def provider_name
    "plaid"
  end
  
  def supported_account_types
    %w[depository investment credit loan]
  end
  
  def fetch_holdings(account)
    client.investments_holdings_get(
      access_token: credentials[:access_token]
    ).holdings.map do |holding|
      # Transform to Holding attributes
    end
  end
  
  def fetch_transactions(account, start_date:, end_date:)
    # Plaid transactions fetch
  end
end

class PlaidItem::Syncer
  def sync
    plaid_item.accounts.each do |account|
      Account::Syncer.new(account, sync).sync
    end
  end
end
```

### Example: SimpleFIN Integration

**Location**: `app/models/provider/simplefin.rb`, `app/models/simplefin_item/syncer.rb`

SimpleFIN provides a simpler API focused on account aggregation:

```ruby
class Provider::Simplefin < Provider::Base
  def provider_name
    "simplefin"
  end
  
  def fetch_holdings(account)
    # SimpleFIN holdings fetch
  end
end
```

---

## Common Patterns

### Cost Basis Resolution Flow

```
User enters manual cost_basis
    ↓
Manual set locks cost_basis_source = :manual
    ↓
Provider sync attempts update
    ↓
Holding#cost_basis_replaceable_by?(:provider)
    ↓
Returns false (manual > provider)
    ↓
Provider update skipped, manual cost basis preserved
```

### Security Price Refresh Flow

```
Sync starts
    ↓
Identify unique securities in holdings
    ↓
For each security:
  - Check cache for recent price
  - If stale/missing, call price_provider
  - Store in security_prices table
    ↓
Use cached prices for holding calculations
```

### Linked Account Sync Flow

```
Account#sync_later called
    ↓
Create Sync record (state: pending)
    ↓
SyncJob queued
    ↓
Sync starts (state: syncing)
    ↓
Fetch provider holdings (external source of truth)
    ↓
ReverseCalculator reconstructs history
    ↓
Balance::Materializer creates balance records
    ↓
Sync completes (state: completed)
    ↓
Trigger valuation callbacks, cache updates
```

---

## Related Documentation

- [API Documentation](./api/) - API reference for external integrations
- [Adding a Securities Provider](./llm-guides/adding-a-securities-provider.md) - Guide for adding new price providers
- [Plaid Integration](./hosting/plaid.md) - Plaid-specific setup and configuration

# Policy Kernel Documentation

The Policy Kernel provides a versioned policy system for portfolio management, enabling financial advisors and family offices to define, track, and enforce investment policies across client portfolios.

## Overview

The Policy Kernel consists of four core components:

1. **Policy Versions** - Versioned policy documents with lifecycle management
2. **Sleeves** - Hierarchical asset allocation structure (asset classes)
3. **Guardrails** - Compliance monitoring rules and thresholds
4. **Policy Assignment** - Linking policies to families and accounts

## Policy Version Lifecycle

Policy versions follow a strict state machine:

```
draft → active → archived
```

### States

- **Draft** - Policy is being created/edited, not yet active
- **Active** - Currently enforced policy (only one per family)
- **Archived** - Historical policy, retained for audit/compliance

### State Transitions

```ruby
policy = PolicyVersion.new(family: family, name: "Conservative Growth")
policy.save! # status: draft

policy.activate! # Activates policy, archives any existing active policy
policy.archive! # Archives the policy when superseded
```

### Key Behaviors

- Only one policy version can be `active` per family at any time
- Activating a policy automatically archives the previously active policy
- Archived policies are immutable (retained for compliance)
- Draft policies can be freely modified

## Sleeve Hierarchy and Allocation Math

Sleeves represent asset classes or investment categories within a policy. They support nested hierarchies for granular allocation strategies.

### Structure

```
PolicyVersion
├── Sleeve (US Equities, 60%)
│   ├── Sleeve (Large Cap, 40%)
│   ├── Sleeve (Mid Cap, 12%)
│   └── Sleeve (Small Cap, 8%)
├── Sleeve (International, 25%)
│   ├── Sleeve (Developed, 20%)
│   └── Sleeve (Emerging, 5%)
└── Sleeve (Fixed Income, 15%)
    └── Sleeve (Investment Grade, 15%)
```

### Validation Rules

1. **Root-Level Sum**: Top-level sleeves must sum to exactly 100%
2. **Children Sum**: Child sleeves must sum to exactly parent's target percentage
3. **Percentage Bounds**: Each sleeve can have min/max constraints
4. **No Circular Nesting**: Sleeves cannot be their own ancestors

### Example

```ruby
policy = PolicyVersion.create!(family: family, name: "Balanced", status: "draft")

us_equities = policy.sleeves.create!(
  name: "US Equities",
  target_percentage: 60,
  min_percentage: 50,
  max_percentage: 70,
  color: "#1f77b4"
)

us_equities.child_sleeves.create!(
  name: "Large Cap",
  target_percentage: 40,
  color: "#aec7e8"
)

us_equities.child_sleeves.create!(
  name: "Small Cap",
  target_percentage: 20,
  color: "#ff7f0e"
)

# Validation
policy.target_percentage_valid? # => true (sums to 100)
us_equities.children_target_valid? # => true (40 + 20 = 60)
```

## Guardrail Types and Configuration

Guardrails define compliance rules that are checked against actual portfolio allocations.

### Types

| Type | Description | Configuration |
|------|-------------|---------------|
| `drift_threshold` | Maximum allowed drift from target | `threshold: 5.0` (percent) |
| `concentration_limit` | Max allocation to a single sleeve | `threshold: 40.0` (percent) |
| `cash_minimum` | Minimum cash allocation required | `threshold: 2.0` (percent) |
| `cash_maximum` | Maximum cash allocation allowed | `threshold: 10.0` (percent) |
| `rebalance_frequency` | Days between required rebalances | `threshold: 90` (days) |
| `single_security_limit` | Max position in single security | `threshold: 5.0` (percent) |
| `sector_concentration` | Max sector allocation | `threshold: 25.0` (percent) |
| `geographic_exposure` | Geographic concentration limits | `threshold: 50.0` (percent) |
| `tax_loss_harvesting` | TLH opportunity threshold | `threshold: 5000` (dollars) |

### Severity Levels

- **Critical** - Requires immediate attention (e.g., >10% drift)
- **Warning** - Should be addressed (e.g., >5% drift)
- **Info** - Informational only (e.g., rebalance reminder)

### Example

```ruby
policy.guardrails.create!(
  name: "Drift Monitor",
  guardrail_type: "drift_threshold",
  severity: "warning",
  configuration: { threshold: 5.0 }
)

policy.guardrails.create!(
  name: "Cash Position",
  guardrail_type: "cash_maximum",
  severity: "critical",
  configuration: { threshold: 15.0 }
)

# Checking compliance
guardrail = policy.guardrails.find_by(guardrail_type: "drift_threshold")
result = guardrail.check(7.5) # Current drift is 7.5%
# => { passed: false, message: "Drift of 7.5% exceeds threshold of 5.0%" }
```

## Policy Flow: Family → Accounts → Holdings

Policies cascade down from families to individual holdings:

```
┌─────────────────┐
│     Family      │◄─── policy_version_id (optional)
│  (e.g., Smith)  │
└────────┬────────┘
         │ has many
         ▼
┌─────────────────┐     ┌─────────────────┐
│     Account     │◄────┤ policy_override │ (JSONB for exceptions)
│  (Investment)   │     │ { "sleeve_id":  │
└────────┬────────┘     │   "exclude": []}│
         │ has many     └─────────────────┘
         ▼
┌─────────────────┐
│    Holdings     │
│  (AAPL, MSFT)   │
└─────────────────┘
```

### Inheritance Rules

1. **Family Level**: Family has an optional `policy_version_id`
   - If set, all accounts in the family inherit this policy by default
   - If nil, no policy enforcement (legacy behavior)

2. **Account Level**: Accounts have `policy_override` (JSONB)
   - Can exclude specific sleeves from policy
   - Can set account-specific guardrail overrides
   - Stored as flexible JSONB for extensibility

3. **Holding Level**: Holdings are matched to sleeves
   - Securities map to sleeve categories
   - Drift calculated per sleeve vs. target
   - Guardrails checked against actual allocations

### Example

```ruby
# Assign policy to family
family.update!(policy_version_id: policy.id)

# Account with override
account.update!(
  policy_override: {
    excluded_sleeves: [small_cap_sleeve.id],
    guardrail_overrides: {
      "cash_maximum" => 20.0  # Higher limit for this account
    }
  }
)

# Get effective configuration
config = policy.configuration_with_inheritance
# => {
#   "sleeves" => [...],
#   "guardrails" => [...],
#   "overrides" => {...}
# }
```

## Database Schema

### policy_versions
- `id` (uuid, PK)
- `family_id` (uuid, required) - Owning family
- `name` (string, required) - Policy name
- `description` (text) - Optional description
- `status` (string, default: draft) - Lifecycle state
- `effective_date` (date) - When policy becomes effective
- `created_by_id` (uuid, required) - User who created it
- `configuration` (jsonb, default: {}) - Flexible policy rules
- `timestamps`

Indexes: family_id, status, effective_date, configuration (GIN)

### sleeves
- `id` (uuid, PK)
- `policy_version_id` (uuid, required, FK) - Parent policy
- `name` (string, required) - Sleeve name
- `description` (text) - Optional description
- `target_percentage` (decimal 5,2, required) - Target allocation
- `min_percentage` (decimal 5,2) - Minimum allowed
- `max_percentage` (decimal 5,2) - Maximum allowed
- `sort_order` (integer, default: 0) - Display order
- `color` (string) - Visualization color
- `parent_sleeve_id` (uuid, FK) - For nested sleeves
- `timestamps`

Indexes: policy_version_id, parent_sleeve_id
Foreign Keys: policy_versions (cascade), sleeves (cascade)

### guardrails
- `id` (uuid, PK)
- `policy_version_id` (uuid, required, FK) - Parent policy
- `name` (string, required) - Guardrail name
- `guardrail_type` (string, required) - Type enum
- `configuration` (jsonb, default: {}) - Type-specific config
- `severity` (string, default: warning) - warning/critical/info
- `enabled` (boolean, default: true) - Active flag
- `description` (text) - Optional description
- `timestamps`

Indexes: policy_version_id, guardrail_type, severity, enabled, configuration (GIN)
Foreign Key: policy_versions (cascade)

### families (updated)
- `policy_version_id` (uuid, nullable, FK) - Current active policy

Indexes: policy_version_id
Foreign Key: policy_versions (nullify on delete)

### accounts (updated)
- `policy_override` (jsonb, default: {}) - Account-specific exceptions

Indexes: policy_override (GIN)

## Common Operations

### Creating a New Policy

```ruby
policy = family.policy_versions.create!(
  name: "Growth Portfolio",
  description: "Aggressive growth strategy for younger investors",
  created_by: advisor,
  status: "draft"
)

# Add sleeves
policy.sleeves.create!(name: "US Equities", target_percentage: 50, color: "#1f77b4")
policy.sleeves.create!(name: "International", target_percentage: 30, color: "#ff7f0e")
policy.sleeves.create!(name: "Fixed Income", target_percentage: 20, color: "#2ca02c")

# Add guardrails
policy.guardrails.create!(
  name: "Drift Warning",
  guardrail_type: "drift_threshold",
  severity: "warning",
  configuration: { threshold: 5.0 }
)

# Activate
policy.activate! # Makes policy active and archives previous
```

### Checking Compliance

```ruby
# Get all guardrails for a family
family.policy_versions.active.guardrails.enabled.each do |guardrail|
  result = guardrail.check(calculated_value, context)
  unless result[:passed]
    puts "#{guardrail.name}: #{result[:message]}"
  end
end
```

### Copying a Policy (Versioning)

```ruby
old_policy = family.policy_versions.active
new_policy = old_policy.dup
data = old_policy.configuration_with_inheritance
new_policy.name = "#{old_policy.name} (v2)"
new_policy.status = "draft"
new_policy.save!

# Copy sleeves
data["sleeves"].each do |sleeve_data|
  copy_sleeve_recursive(new_policy, sleeve_data)
end

# Copy guardrails
data["guardrails"].each do |guardrail_data|
  new_policy.guardrails.create!(guardrail_data)
end
```

## Future Enhancements

Planned features for future phases:

1. **Policy Templates** - Pre-defined policy templates for common strategies
2. **Automated Rebalancing** - Trigger rebalances when drift exceeds thresholds
3. **Tax-Aware Rebalancing** - Consider tax implications in rebalancing decisions
4. **ESG Integration** - ESG scoring and policy constraints
5. **Scenario Analysis** - Monte Carlo simulation for policy outcomes
6. **Client Reporting** - Automated policy compliance reports

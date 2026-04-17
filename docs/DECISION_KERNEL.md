# Decision Kernel Documentation

The Decision Kernel provides an intelligent decision support system for portfolio management, enabling financial advisors and family offices to prioritize actions, generate recommendations, and maintain a complete audit trail of all portfolio decisions.

## Table of Contents

- [Overview](#overview)
- [Top Action System](#top-action-system)
- [Recommendation Engine](#recommendation-engine)
- [Decision Audit Trail](#decision-audit-trail)
- [Integration with Policy Kernel](#integration-with-policy-kernel)
- [Database Schema](#database-schema)
- [Usage Examples](#usage-examples)

---

## Overview

The Decision Kernel enables proactive portfolio management through:

1. **Top Action System** - Priority-ranked actionable items that require attention
2. **Recommendation Engine** - Data-driven suggestions with approval workflow
3. **Decision Audit Trail** - Immutable logging of all decisions for compliance
4. **Policy Integration** - Automatic detection of policy drift and guardrail violations

### Key Design Principles

1. **Prioritization-Based Workflow**: Actions are scored and surfaced based on urgency and impact
2. **Human-in-the-Loop**: Recommendations require human approval before execution
3. **Immutable Audit Trail**: All decisions are logged for compliance and accountability
4. **Policy-Aware**: Deep integration with the Policy Kernel for drift detection

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Decision Kernel                           │
├─────────────────┬─────────────────┬─────────────────────────────┤
│  Top Action     │  Recommendation │      Decision Log           │
│     System      │     Engine      │      (Audit Trail)          │
├─────────────────┼─────────────────┼─────────────────────────────┤
│ • Priorities    │ • Trade recs    │ • Action dismissed          │
│ • Lifecycle     │ • Rebalance recs│ • Recommendation approved   │
│ • Auto-expiry   │ • Cash flow recs│ • Recommendation rejected   │
│                 │                 │ • Manual overrides          │
└────────┬────────┴────────┬────────┴──────────────┬──────────────┘
         │                 │                       │
         ▼                 ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Policy Kernel Integration                     │
│  • Drift detection triggers Top Actions                         │
│  • Guardrail violations generate Recommendations                │
│  • Policy compliance tracked in Decision Logs                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Top Action System

The Top Action System identifies and prioritizes portfolio management tasks that require attention. Each action represents a discrete item that an advisor or portfolio manager should address.

### Action Types

| Action Type | Description | Priority Range | Typical Source |
|-------------|-------------|----------------|----------------|
| `rebalance_needed` | Portfolio drift exceeds threshold | 8-10 | Policy Kernel drift detection |
| `policy_drift` | Allocation drift from target percentages | 6-9 | Sleeve drift calculation |
| `data_quality` | Missing or stale portfolio data | 5-8 | Sync failures, missing prices |
| `cash_idle` | Excess cash not invested | 4-7 | Cash allocation analysis |
| `manual_review` | Items requiring human review | 3-6 | Exception handling |
| `compliance_issue` | Policy guardrail violations | 9-10 | Guardrail check failures |

### Action Lifecycle

Top actions follow a simple state machine:

```
created → active → [dismissed | completed]
```

**Active**: Action is visible and actionable  
**Dismissed**: Action was acknowledged but not acted upon  
**Completed**: Action was addressed and resolved  
**Expired**: Action is older than 30 days and no longer relevant  

### Priority Scoring

Priority is an integer from 1 (lowest) to 10 (highest) that determines display order:

```ruby
# Critical - requires immediate attention
priority: 10  # Compliance violations, critical drift

# High - should be addressed within 24-48 hours
priority: 8-9  # Rebalance needed, significant drift

# Medium - address within a week
priority: 5-7  # Cash idle, minor drift

# Low - informational
priority: 1-4  # Manual reviews, data quality issues
```

### Context Data

Each action can include rich context data to provide sufficient information:

```ruby
{
  "drift_percentage" => 7.5,
  "sleeve_name" => "US Equities",
  "target_percentage" => 50.0,
  "current_percentage" => 57.5,
  "accounts_affected" => ["uuid-1", "uuid-2"],
  "guardrail_id" => "guardrail-uuid",
  "last_sync_at" => "2025-04-15T10:30:00Z"
}
```

### Action Model

**Location**: `app/models/top_action.rb`

```ruby
class TopAction < ApplicationRecord
  belongs_to :family

  # Core attributes
  attribute :action_type    # Type of action (enum)
  attribute :priority       # 1-10 priority score
  attribute :title          # Display title
  attribute :description    # Detailed description
  attribute :context_data   # JSONB context information

  # Lifecycle timestamps
  attribute :dismissed_at   # When action was dismissed
  attribute :completed_at   # When action was completed

  # State queries
  scope :active, -> { where(dismissed_at: nil, completed_at: nil) }
  scope :high_priority, -> { where("priority >= ?", 7) }
end
```

### Key Methods

**State Management**:
```ruby
action.dismiss!     # Marks action as dismissed
action.complete!    # Marks action as completed
action.dismissed?   # Check if dismissed
action.completed?   # Check if completed
action.expired?     # Check if older than 30 days
```

**Scoping**:
```ruby
# Active high-priority actions
TopAction.for_family(family).active.high_priority.ordered

# Actions by type
TopAction.for_family(family).by_type("policy_drift").active
```

---

## Recommendation Engine

The Recommendation Engine generates data-driven portfolio suggestions that require human approval before execution. Recommendations formalize the workflow from analysis → suggestion → approval → execution.

### Recommendation Types

| Type | Description | Approval Required | Auto-Executable |
|------|-------------|-------------------|-----------------|
| `trade` | Execute specific buy/sell transactions | Yes | No |
| `rebalance` | Portfolio rebalancing plan | Yes | No |
| `deposit` | Cash deposit recommendation | Yes | No |
| `withdraw` | Cash withdrawal recommendation | Yes | No |
| `review` | Manual review request | No | N/A |

### Recommendation Lifecycle

Recommendations follow a state machine with human checkpoints:

```
     ┌──────────┐
     │  pending │◄─────────────────────┐
     └────┬─────┘                      │
          │                            │
    ┌─────┴─────┐                      │
    │           │                      │
    ▼           ▼                      │
┌────────┐  ┌──────────┐              │
│approved│  │ rejected │──────────────┘
└────┬───┘  └──────────┘
     │
     ▼
┌──────────┐
│ executed │
└──────────┘
```

### Approval Workflow

```ruby
# Generate recommendation
recommendation = Recommendation.create!(
  family: family,
  policy_version: policy,
  recommendation_type: "rebalance",
  title: "Rebalance US Equities",
  description: "Drift of 7.5% exceeds threshold",
  details: {
    trades: [...],
    total_amount: 25000,
    rationale: "Sleeve drift requires rebalancing"
  }
)

# Advisor reviews and approves
recommendation.approve!(current_user)

# Execute trades
recommendation.execute!  # Status changes to "executed"

# Or reject with rationale
recommendation.reject!(current_user)
DecisionLog.log_decision(
  family: family,
  actor: current_user,
  decision_type: "recommendation_rejected",
  reference: recommendation,
  rationale: "Client prefers to wait until next quarter"
)
```

### Details Structure

The `details` JSONB field contains recommendation-specific data:

**Trade Recommendation**:
```ruby
{
  "trades" => [
    {
      "account_id" => "uuid",
      "security_id" => "uuid",
      "action" => "buy",
      "quantity" => 100,
      "estimated_price" => 150.00,
      "estimated_amount" => 15000.00
    }
  ],
  "total_amount" => 25000.00,
  "rationale" => "Rebalance US Equities to target allocation"
}
```

**Rebalance Recommendation**:
```ruby
{
  "drift_analysis" => {
    "total_drift" => 7.5,
    "sleeves" => [...]
  },
  "target_allocation" => { ... },
  "proposed_trades" => [...],
  "estimated_cost" => 25.00,
  "tax_impact" => "minimal"
}
```

### Recommendation Model

**Location**: `app/models/recommendation.rb`

```ruby
class Recommendation < ApplicationRecord
  belongs_to :family
  belongs_to :policy_version, optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  # Core attributes
  attribute :recommendation_type  # Type enum
  attribute :status              # pending/approved/rejected/executed
  attribute :title               # Display title
  attribute :description         # Detailed description
  attribute :details             # JSONB recommendation data

  # Workflow timestamps
  attribute :executed_at         # When recommendation was executed

  # State predicates
  def pending?;   status == "pending";   end
  def approved?;  status == "approved";  end
  def rejected?;  status == "rejected";  end
  def executed?;  status == "executed";  end
end
```

### Generating Recommendations

The recommendation generation process typically involves:

1. **Analysis**: Calculate drift, cash positions, tax-loss opportunities
2. **Validation**: Check against guardrails and constraints
3. **Construction**: Build recommendation with trades/rationale
4. **Presentation**: Surface to advisor for review
5. **Logging**: Record in decision audit trail

```ruby
# Example: Generate rebalance recommendation from drift analysis
if drift_percentage > threshold
  recommendation = RecommendationBuilder.build_rebalance(
    family: family,
    policy: policy,
    drift_analysis: drift_analysis,
    trades: TradeGenerator.generate_trades(drift_analysis)
  )

  # Create associated top action for visibility
  TopActionGenerator.create_from_recommendation(recommendation)
end
```

---

## Decision Audit Trail

The Decision Log provides an immutable record of all portfolio decisions for compliance, accountability, and historical analysis.

### Decision Types

| Decision Type | Description | Reference Type |
|---------------|-------------|----------------|
| `action_dismissed` | Top action was dismissed without action | TopAction |
| `recommendation_approved` | Recommendation was approved | Recommendation |
| `recommendation_rejected` | Recommendation was rejected | Recommendation |
| `manual_override` | Manual override of automated decision | Varies |

### Logging Pattern

Every decision is logged with:

- **Who**: The actor (user) making the decision
- **What**: The decision type and reference to the affected entity
- **When**: Precise timestamp
- **Why**: Rationale/explanation for the decision
- **Context**: Metadata for additional context

```ruby
# Log a dismissed action
DecisionLog.log_decision(
  family: family,
  actor: current_user,
  decision_type: "action_dismissed",
  reference: top_action,
  rationale: "Drift has already been addressed in recent rebalance",
  metadata: {
    original_priority: 8,
    action_type: "policy_drift",
    days_since_created: 3
  }
)

# Log an approved recommendation
DecisionLog.log_decision(
  family: family,
  actor: current_user,
  decision_type: "recommendation_approved",
  reference: recommendation,
  rationale: "Approved based on Q2 rebalancing strategy",
  metadata: {
    recommendation_type: "rebalance",
    total_amount: 25000,
    estimated_trades: 4
  }
)
```

### Decision Log Model

**Location**: `app/models/decision_log.rb`

```ruby
class DecisionLog < ApplicationRecord
  belongs_to :family
  belongs_to :actor, class_name: "User"

  # Polymorphic reference to the decision subject
  attribute :reference_type  # Class name of reference
  attribute :reference_id    # ID of reference
  attribute :decision_type   # Type enum
  attribute :rationale       # Explanation
  attribute :metadata        # JSONB context

  # Retrieve the referenced object
  def reference
    @reference ||= reference_type.constantize.find_by(id: reference_id)
  end
end
```

### Querying the Audit Trail

```ruby
# Recent decisions for a family
DecisionLog.for_family(family).recent.limit(50)

# All decisions for a specific recommendation
DecisionLog.for_reference(recommendation)

# Decisions by type
DecisionLog.for_family(family).by_type("recommendation_approved")

# Decisions since a date
DecisionLog.for_family(family).since(30.days.ago)

# Decisions by a specific advisor
DecisionLog.for_family(family).by_actor(advisor_user)
```

### Compliance Use Cases

**Regulatory Reporting**:
```ruby
# Generate compliance report for period
logs = DecisionLog.for_family(family).since(reporting_period_start)

report = logs.map do |log|
  {
    date: log.created_at,
    decision: log.decision_type,
    actor: log.actor.email,
    rationale: log.rationale,
    reference: log.reference_type
  }
end
```

**Decision Pattern Analysis**:
```ruby
# Analyze rejection reasons for recommendations
rejections = DecisionLog
  .for_family(family)
  .by_type("recommendation_rejected")
  .since(90.days.ago)

# Group by rationale to identify common concerns
rejection_reasons = rejections.group_by(&:rationale).transform_values(&:count)
```

---

## Integration with Policy Kernel

The Decision Kernel integrates deeply with the Policy Kernel to detect drift, monitor compliance, and trigger actions automatically.

### Drift Detection Flow

```
┌─────────────────┐
│ Policy Version  │
│ (Active Policy) │
└────────┬────────┘
         │ has_many
         ▼
┌─────────────────┐     ┌──────────────────┐
│     Sleeves     │────▶│  Target vs Actual │
│  (Allocations)  │     │  Comparison      │
└─────────────────┘     └────────┬─────────┘
                                 │
                                 ▼
                        ┌──────────────────┐
                        │  Drift Analysis  │
                        │  (percentage,    │
                        │   dollar amount) │
                        └────────┬─────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
            ┌──────────┐  ┌──────────┐  ┌──────────┐
            │Guardrail │  │  Top     │  │   Top    │
            │  Check   │  │  Action  │  │  Action  │
            │          │  │(Critical)│  │ (Warning)│
            └──────────┘  └──────────┘  └──────────┘
```

### Automatic Action Generation

When drift exceeds thresholds, the system automatically creates actions:

```ruby
# Drift exceeds critical threshold (e.g., 10%)
if drift > 10.0
  TopAction.create!(
    family: family,
    action_type: "policy_drift",
    priority: 10,
    title: "Critical: Portfolio Drift Exceeds 10%",
    description: "Immediate rebalancing required",
    context_data: {
      drift_percentage: drift,
      sleeve_name: sleeve.name,
      threshold: 10.0
    }
  )

  # Also create guardrail violation log
  DecisionLog.log_decision(
    family: family,
    actor: SystemUser.current,
    decision_type: "manual_override",  # System-generated
    reference: guardrail,
    rationale: "Critical guardrail violation detected",
    metadata: { auto_generated: true, drift: drift }
  )

# Drift exceeds warning threshold (e.g., 5%)
elsif drift > 5.0
  TopAction.create!(
    family: family,
    action_type: "policy_drift",
    priority: 7,
    title: "Warning: Portfolio Drift at #{drift}%",
    context_data: { drift_percentage: drift, threshold: 5.0 }
  )
end
```

### Guardrail Integration

Guardrails from the Policy Kernel automatically generate appropriate actions:

```ruby
# Check each enabled guardrail
policy.guardrails.enabled.each do |guardrail|
  result = guardrail.check(calculated_value, context)

  unless result[:passed]
    # Determine priority based on severity
    priority = guardrail.critical? ? 10 : (guardrail.warning? ? 7 : 4)

    action_type = case guardrail.guardrail_type
                  when "drift_threshold" then "policy_drift"
                  when "concentration_limit" then "compliance_issue"
                  when "cash_maximum", "cash_minimum" then "cash_idle"
                  else "compliance_issue"
                  end

    TopAction.create!(
      family: family,
      action_type: action_type,
      priority: priority,
      title: "#{guardrail.name}: #{result[:message]}",
      context_data: {
        guardrail_id: guardrail.id,
        guardrail_type: guardrail.guardrail_type,
        severity: guardrail.severity,
        message: result[:message]
      }
    )
  end
end
```

### Rebalance Recommendation Integration

When drift is detected, the system can generate rebalancing recommendations:

```ruby
# Detect significant drift
drift_analysis = calculate_drift(family, policy)

if drift_analysis[:total_drift] > drift_threshold
  # Generate rebalancing trades
  trades = RebalanceTradesGenerator.generate(
    policy: policy,
    holdings: family.holdings,
    drift: drift_analysis
  )

  # Create recommendation
  recommendation = Recommendation.create!(
    family: family,
    policy_version: policy,
    recommendation_type: "rebalance",
    title: "Rebalance: #{drift_analysis[:total_drift].round(2)}% Drift Detected",
    description: "Rebalance recommended to restore target allocations",
    details: {
      drift_analysis: drift_analysis,
      proposed_trades: trades,
      estimated_cost: estimate_costs(trades),
      rationale: "Drift exceeds #{drift_threshold}% threshold"
    }
  )

  # Create top action for visibility
  TopAction.create!(
    family: family,
    action_type: "rebalance_needed",
    priority: 8,
    title: "Rebalance Recommendation Pending",
    description: recommendation.title,
    context_data: {
      recommendation_id: recommendation.id,
      drift_percentage: drift_analysis[:total_drift]
    }
  )
end
```

### Policy Change Impact

When policies change, existing actions and recommendations may need review:

```ruby
# When a new policy is activated
policy.activate!

# Invalidate stale drift actions based on old policy
TopAction
  .for_family(family)
  .by_type("policy_drift")
  .active
  .where("created_at < ?", policy.activated_at)
  .find_each(&:dismiss!)

# Create new drift analysis with new policy
DriftAnalyzer.analyze(family, policy)
```

---

## Database Schema

### top_actions

Stores prioritized actionable items for portfolio management.

- `id` (uuid, PK)
- `family_id` (uuid, required, FK) - Owning family
- `action_type` (string, required) - Type enum
- `priority` (integer, default: 5) - 1-10 priority score
- `title` (string, required) - Display title
- `description` (text) - Detailed description
- `context_data` (jsonb, default: {}) - Rich context information
- `dismissed_at` (datetime) - When action was dismissed
- `completed_at` (datetime) - When action was completed
- `timestamps`

**Indexes**:
- `family_id` - Family lookups
- `action_type` - Type filtering
- `priority` - Priority sorting
- `dismissed_at` - Active/dismissed filtering
- `[:family_id, :action_type]` - Combined lookup
- `context_data` (GIN) - JSONB queries

**Foreign Keys**:
- `family_id` → `families` (cascade delete)

### recommendations

Stores data-driven recommendations awaiting approval.

- `id` (uuid, PK)
- `family_id` (uuid, required, FK) - Owning family
- `policy_version_id` (uuid, FK) - Associated policy (optional)
- `recommendation_type` (string, required) - Type enum
- `status` (string, default: "pending") - Workflow state
- `title` (string, required) - Display title
- `description` (text) - Detailed description
- `details` (jsonb, default: {}) - Recommendation data (trades, amounts, etc.)
- `approved_by_id` (uuid, FK) - User who approved/rejected
- `executed_at` (datetime) - When recommendation was executed
- `timestamps`

**Indexes**:
- `family_id` - Family lookups
- `policy_version_id` - Policy association
- `recommendation_type` - Type filtering
- `status` - Status filtering
- `approved_by_id` - Approver lookups
- `[:family_id, :status]` - Combined lookup
- `details` (GIN) - JSONB queries

**Foreign Keys**:
- `family_id` → `families` (cascade delete)
- `policy_version_id` → `policy_versions` (nullify on delete)
- `approved_by_id` → `users` (nullify on delete)

### decision_logs

Immutable audit trail of all portfolio decisions.

- `id` (uuid, PK)
- `family_id` (uuid, required, FK) - Owning family
- `decision_type` (string, required) - Type enum
- `actor_id` (uuid, required, FK) - User who made the decision
- `reference_type` (string, required) - Polymorphic reference class
- `reference_id` (uuid, required) - Polymorphic reference ID
- `rationale` (text) - Explanation for the decision
- `metadata` (jsonb, default: {}) - Additional context
- `timestamps`

**Indexes**:
- `family_id` - Family lookups
- `decision_type` - Type filtering
- `actor_id` - Actor filtering
- `[:reference_type, :reference_id]` - Polymorphic lookups
- `[:family_id, :created_at]` - Chronological queries
- `metadata` (GIN) - JSONB queries

**Foreign Keys**:
- `family_id` → `families` (cascade delete)
- `actor_id` → `users` (cascade delete)

---

## Usage Examples

### Daily Portfolio Review Workflow

```ruby
# Get all high-priority actions for morning review
def daily_review(family)
  actions = TopAction
    .for_family(family)
    .active
    .high_priority
    .ordered

  actions.each do |action|
    puts "#{action.priority}: #{action.title}"
    puts "  #{action.description}"
    puts "  Context: #{action.context_data}"
  end

  actions
end

# Process each action
family.top_actions.active.high_priority.each do |action|
  case action.action_type
  when "policy_drift"
    handle_drift_action(action)
  when "rebalance_needed"
    handle_rebalance_action(action)
  when "data_quality"
    handle_data_quality_action(action)
  end
end
```

### Creating a Manual Top Action

```ruby
# Advisor creates manual review request
action = TopAction.create!(
  family: family,
  action_type: "manual_review",
  priority: 5,
  title: "Review Concentrated Position",
  description: "AAPL position exceeds 10% of portfolio",
  context_data: {
    security_id: aapl.id,
    security_name: "Apple Inc.",
    position_percentage: 12.5,
    threshold: 10.0,
    market_value: 150000
  }
)
```

### Generating a Rebalance Recommendation

```ruby
# Calculate current drift
drift_analysis = DriftAnalyzer.new(policy).calculate

# Create recommendation if drift exceeds threshold
if drift_analysis[:total_drift] > 5.0
  trades = TradeGenerator.generate_rebalance_trades(
    policy: policy,
    drift: drift_analysis
  )

  recommendation = Recommendation.create!(
    family: family,
    policy_version: policy,
    recommendation_type: "rebalance",
    title: "Rebalance Portfolio - #{drift_analysis[:total_drift].round(1)}% Drift",
    description: "Rebalancing recommended to restore target allocations",
    details: {
      drift_analysis: drift_analysis,
      proposed_trades: trades,
      estimated_cost: calculate_costs(trades),
      tax_impact: estimate_tax_impact(trades),
      rationale: "Drift exceeds 5% threshold"
    }
  )

  # Create top action for visibility
  TopAction.create!(
    family: family,
    action_type: "rebalance_needed",
    priority: 8,
    title: "Review Rebalance Recommendation",
    description: recommendation.title,
    context_data: {
      recommendation_id: recommendation.id,
      drift: drift_analysis[:total_drift],
      trade_count: trades.count
    }
  )
end
```

### Processing Recommendation Approval

```ruby
class RecommendationsController < ApplicationController
  def approve
    recommendation = family.recommendations.find(params[:id])

    if recommendation.approve!(current_user)
      # Log the decision
      DecisionLog.log_decision(
        family: family,
        actor: current_user,
        decision_type: "recommendation_approved",
        reference: recommendation,
        rationale: params[:rationale],
        metadata: {
          trade_count: recommendation.trades.count,
          total_amount: recommendation.total_amount
        }
      )

      # Complete the associated top action
      TopAction
        .for_family(family)
        .active
        .find_by("context_data->>'recommendation_id' = ?", recommendation.id)
        &.complete!

      redirect_to recommendations_path, notice: "Recommendation approved"
    else
      redirect_to recommendations_path, alert: "Could not approve recommendation"
    end
  end

  def reject
    recommendation = family.recommendations.find(params[:id])

    if recommendation.reject!(current_user)
      DecisionLog.log_decision(
        family: family,
        actor: current_user,
        decision_type: "recommendation_rejected",
        reference: recommendation,
        rationale: params[:rationale]
      )

      # Dismiss the associated top action
      TopAction
        .for_family(family)
        .active
        .find_by("context_data->>'recommendation_id' = ?", recommendation.id)
        &.dismiss!

      redirect_to recommendations_path, notice: "Recommendation rejected"
    end
  end
end
```

### Compliance Reporting

```ruby
class ComplianceReport
  def generate(family, start_date:, end_date:)
    logs = DecisionLog
      .for_family(family)
      .where(created_at: start_date..end_date)
      .order(:created_at)

    {
      period: "#{start_date} to #{end_date}",
      total_decisions: logs.count,
      by_type: logs.group(:decision_type).count,
      by_actor: logs.joins(:actor).group("users.email").count,
      recommendations: {
        approved: logs.by_type("recommendation_approved").count,
        rejected: logs.by_type("recommendation_rejected").count
      },
      details: logs.map do |log|
        {
          date: log.created_at,
          type: log.decision_type,
          actor: log.actor.email,
          rationale: log.rationale,
          reference: "#{log.reference_type}##{log.reference_id}"
        }
      end
    }
  end
end
```

### Action Expiration Cleanup

```ruby
# Rake task to clean up expired actions
task cleanup_expired_actions: :environment do
  expired = TopAction
    .active
    .where("created_at < ?", 30.days.ago)

  count = 0
  expired.find_each do |action|
    action.dismiss!
    count += 1
  end

  puts "Dismissed #{count} expired actions"
end
```

---

## Related Documentation

- [Policy Kernel](./POLICY_KERNEL.md) - Policy versions, sleeves, and guardrails
- [Investment Kernel](./INVESTMENT_KERNEL.md) - Holdings, trades, and valuations
- [API Documentation](./api/) - API reference for decision endpoints

## Future Enhancements

Planned features for future phases:

1. **Automated Rebalancing** - Option to auto-execute approved recommendations
2. **Tax-Loss Harvesting Recommendations** - Automated TLH opportunity detection
3. **Recurring Review Schedules** - Time-based action generation
4. **Advisor Assignment** - Assign actions to specific team members
5. **Client Notifications** - Surface actions to clients for approval
6. **ML-Based Prioritization** - Learn from advisor behavior to improve prioritization
7. **Decision Analytics Dashboard** - Visualize decision patterns and outcomes

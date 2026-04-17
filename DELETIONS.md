# Sure Codebase Deletions - Phase 1: Consumer PFM Non-Goals

## Overview
This document tracks all code deleted during Phase 1 of the Portfolio Operating System transformation.
The goal was to remove all consumer PFM (Personal Finance Management) features to prepare for building
the investment-focused Portfolio Operating System.

## Date
April 17, 2026

## Deleted Features

### 1. Budgets
**Models:**
- `app/models/budget.rb`
- `app/models/budget_category.rb`

**Controllers:**
- `app/controllers/budgets_controller.rb`
- `app/controllers/budget_categories_controller.rb`

**Views:**
- `app/views/budgets/` (entire directory)
- `app/views/budget_categories/` (entire directory)

**Tests:**
- `test/models/budget_test.rb`
- `test/models/budget_category_test.rb`
- `test/controllers/budgets_controller_test.rb`
- `test/controllers/budget_categories_controller_test.rb`
- `test/helpers/budgets_helper_test.rb`

**Helpers:**
- `app/helpers/budgets_helper.rb`

**JavaScript:**
- `app/javascript/controllers/budget_filter_controller.js`
- `app/javascript/controllers/budget_form_controller.js`

**Locales:**
- `config/locales/views/budgets/` (entire directory)

**Fixtures:**
- `test/fixtures/budgets.yml`
- `test/fixtures/budget_categories.yml`

---

### 2. Categories
**Models:**
- `app/models/category.rb`
- `app/models/category_import.rb`
- `app/models/import/category_mapping.rb`

**Controllers:**
- `app/controllers/categories_controller.rb`
- `app/controllers/category/deletions_controller.rb`
- `app/controllers/category/dropdowns_controller.rb`
- `app/controllers/transaction_categories_controller.rb`
- `app/controllers/transactions/categorizes_controller.rb`

**Views:**
- `app/views/categories/` (entire directory)
- `app/views/category/` (entire directory)
- `app/views/transactions/_transaction_category.html.erb`
- `app/views/transactions/categorizes/` (entire directory)
- `app/views/transactions/searches/filters/_category_filter.html.erb`

**Tests:**
- `test/models/category_test.rb`
- `test/models/category_import_test.rb`
- `test/controllers/categories_controller_test.rb`
- `test/controllers/category/deletions_controller_test.rb`
- `test/system/categories_test.rb`

**JavaScript:**
- `app/javascript/controllers/categorize_controller.js`
- `app/javascript/controllers/category_badge_select_controller.js`
- `app/javascript/controllers/category_controller.js`

**Locales:**
- `config/locales/views/categories/` (entire directory)
- `config/locales/models/category/` (entire directory)

**Fixtures:**
- `test/fixtures/categories.yml`

**Other:**
- `app/models/plaid_account/transactions/category_matcher.rb`
- `app/models/plaid_account/transactions/category_taxonomy.rb`

---

### 3. Merchants
**Models:**
- `app/models/merchant.rb`
- `app/models/merchant/merger.rb`
- `app/models/family_merchant.rb`
- `app/models/family_merchant_association.rb`
- `app/models/provider_merchant.rb`
- `app/models/provider_merchant/enhancer.rb`

**Controllers:**
- `app/controllers/merchants_controller.rb`
- `app/controllers/family_merchants_controller.rb`

**Views:**
- `app/views/merchants/` (entire directory)
- `app/views/family_merchants/` (entire directory)
- `app/views/transactions/searches/filters/_merchant_filter.html.erb`

**Tests:**
- `test/controllers/family_merchants_controller_test.rb`
- `test/controllers/merchants_controller_test.rb`
- `test/models/provider_merchant/enhancer_test.rb`
- `test/controllers/api/v1/merchants_controller_test.rb`

**JavaScript:**
- (No merchant-specific JS controllers found)

**Locales:**
- `config/locales/views/merchants/` (entire directory)

**Fixtures:**
- `test/fixtures/merchants.yml`

**Other:**
- `app/models/simplefin_account/transactions/merchant_detector.rb`
- `app/models/provider/openai/auto_merchant_detector.rb`
- `app/models/provider/openai/provider_merchant_enhancer.rb`
- `app/models/family/auto_merchant_detector.rb`

---

### 4. Transfers
**Models:**
- `app/models/transfer.rb`
- `app/models/transfer/creator.rb`
- `app/models/rejected_transfer.rb`
- `app/models/transaction/transferable.rb` (module)

**Controllers:**
- `app/controllers/transfers_controller.rb`
- `app/controllers/transfer_matches_controller.rb`

**Views:**
- `app/views/transfers/` (entire directory)
- `app/views/transfer_matches/` (entire directory)
- `app/views/transactions/_transfer_match.html.erb`

**Tests:**
- `test/models/transfer_test.rb`
- `test/models/transfer/creator_test.rb`
- `test/controllers/transfers_controller_test.rb`
- `test/controllers/transfer_matches_controller_test.rb`
- `test/system/transfers_test.rb`

**JavaScript:**
- `app/javascript/controllers/transfer_form_controller.js`
- `app/javascript/controllers/transfer_match_controller.js`

**Locales:**
- `config/locales/views/transfers/` (entire directory)
- `config/locales/models/transfer/` (entire directory)

**Fixtures:**
- `test/fixtures/transfers.yml`

**Concerns:**
- `app/models/family/auto_transfer_matchable.rb` (removed from Family model)

---

### 5. Rules (Auto-categorization)
**Models:**
- `app/models/rule.rb`
- `app/models/rule_run.rb`
- `app/models/rule_import.rb`
- `app/models/rule/action.rb`
- `app/models/rule/condition.rb`
- `app/models/rule/action_executor.rb`
- `app/models/rule/condition_filter.rb`
- `app/models/rule/registry.rb`
- `app/models/rule/action_executor/*.rb` (all files in directory)
- `app/models/rule/condition_filter/*.rb` (all files in directory)
- `app/models/rule/registry/*.rb` (all files in directory)
- `app/models/transaction/ruleable.rb` (module)

**Controllers:**
- `app/controllers/rules_controller.rb`

**Views:**
- `app/views/rules/` (entire directory)
- `app/views/rule/` (entire directory)

**Jobs:**
- `app/jobs/rule_job.rb`
- `app/jobs/apply_all_rules_job.rb`
- `app/jobs/auto_categorize_job.rb`
- `app/jobs/auto_detect_merchants_job.rb`

**Tests:**
- `test/models/rule_test.rb`
- `test/models/rule_import_test.rb`
- `test/models/rule/action_test.rb`
- `test/models/rule/condition_test.rb`
- `test/controllers/rules_controller_test.rb`
- `test/jobs/apply_all_rules_job_test.rb`

**JavaScript:**
- `app/javascript/controllers/rules_controller.js`
- `app/javascript/controllers/rule/` (entire directory)

**Locales:**
- `config/locales/views/rules/` (entire directory)

**Fixtures:**
- `test/fixtures/rules.yml`
- `test/fixtures/rule/actions.yml`
- `test/fixtures/rule/conditions.yml`

**Rake Tasks:**
- `lib/tasks/rules.rake`

**Other:**
- `app/models/provider/openai/auto_categorizer.rb`
- `app/models/family/auto_categorizer.rb`

---

### 6. Recurring Transactions
**Models:**
- `app/models/recurring_transaction.rb`
- `app/models/recurring_transaction/identifier.rb`
- `app/models/recurring_transaction/cleaner.rb`

**Controllers:**
- `app/controllers/recurring_transactions_controller.rb`

**Views:**
- `app/views/recurring_transactions/` (entire directory)

**Tests:**
- `test/models/recurring_transaction_test.rb`
- `test/models/recurring_transaction/identifier_test.rb`
- `test/controllers/recurring_transactions_controller_test.rb`

**Jobs:**
- `app/jobs/identify_recurring_transactions_job.rb`

**Locales:**
- `config/locales/views/recurring_transactions/` (entire directory)

**Fixtures:**
- `test/fixtures/recurring_transactions.yml`

---

### 7. Imports
**Models:**
- `app/models/import.rb`
- `app/models/import/row.rb`
- `app/models/import/mapping.rb`
- `app/models/import/account_mapping.rb`
- `app/models/import/account_type_mapping.rb`
- `app/models/import/tag_mapping.rb`
- `app/models/account_import.rb`
- `app/models/mint_import.rb`
- `app/models/pdf_import.rb`
- `app/models/qif_import.rb`
- `app/models/sure_import.rb`
- `app/models/trade_import.rb`
- `app/models/transaction_import.rb`

**Controllers:**
- `app/controllers/imports_controller.rb`
- `app/controllers/import/uploads_controller.rb`
- `app/controllers/import/configurations_controller.rb`
- `app/controllers/import/cleans_controller.rb`
- `app/controllers/import/confirms_controller.rb`
- `app/controllers/import/mappings_controller.rb`
- `app/controllers/import/rows_controller.rb`
- `app/controllers/import/qif_category_selections_controller.rb`
- `app/controllers/api/v1/imports_controller.rb`

**Views:**
- `app/views/imports/` (entire directory)
- `app/views/import/` (entire directory)
- `app/views/layouts/imports.html.erb`
- `app/views/pdf_import_mailer/` (entire directory)
- `app/views/api/v1/imports/` (entire directory)

**Jobs:**
- `app/jobs/import_job.rb`
- `app/jobs/revert_import_job.rb`
- `app/jobs/process_pdf_job.rb`
- `app/jobs/import_market_data_job.rb`

**Tests:**
- `test/controllers/imports_controller_test.rb`
- `test/controllers/import/*.rb` (all import controller tests)
- `test/jobs/import_job_test.rb`
- `test/system/imports_test.rb`
- `test/interfaces/import_interface_test.rb`
- `test/models/import_encoding_test.rb`
- `test/models/account_import_test.rb`

**Helpers:**
- `app/helpers/imports_helper.rb`

**Mailers:**
- `app/mailers/pdf_import_mailer.rb`

**JavaScript:**
- `app/javascript/controllers/import_controller.js`
- `app/javascript/controllers/drag_and_drop_import_controller.js`
- `app/javascript/controllers/qif_date_format_controller.js`

**Locales:**
- `config/locales/views/imports/` (entire directory)
- `config/locales/models/import/` (entire directory)
- `config/locales/mailers/pdf_import_mailer/` (entire directory)
- `config/locales/views/pdf_import_mailer/` (entire directory)

**Fixtures:**
- `test/fixtures/imports.yml`
- `test/fixtures/import/` (entire directory)
- `test/fixtures/files/imports/` (entire directory)

**Assistant Function:**
- `app/models/assistant/function/import_bank_statement.rb`

---

### 8. Reports (PFM-specific)
**Views:**
- `app/views/reports/_budget_performance.html.erb`
- `app/views/reports/_category_row.html.erb`

**Models:**
- `app/models/income_statement.rb` (entire class)
- `app/models/income_statement/*.rb` (all files)

**Tests:**
- `test/models/income_statement_test.rb`

---

### 9. Evaluation Data
**Files:**
- `db/eval_data/categorization_golden*.yml`
- `db/eval_data/merchant_detection_golden*.yml`

**Models:**
- `app/models/eval/runners/categorization_runner.rb`
- `app/models/eval/runners/merchant_detection_runner.rb`
- `app/models/eval/metrics/categorization_metrics.rb`
- `app/models/eval/metrics/merchant_detection_metrics.rb`

**Tests:**
- `test/models/eval/runners/merchant_detection_runner_test.rb`
- `test/models/eval/metrics/merchant_detection_metrics_test.rb`

---

### 10. Other Deleted Files
**Controllers:**
- `app/controllers/transactions/searches_controller.rb`
- `app/controllers/transactions/bulk_deletions_controller.rb`
- `app/controllers/transactions/bulk_updates_controller.rb`
- `app/controllers/pending_duplicate_merges_controller.rb`
- `app/controllers/splits_controller.rb`

**Views:**
- `app/views/transactions/searches/` (entire directory)
- `app/views/splits/` (entire directory)

**Tests:**
- `test/controllers/transactions/searches_controller_test.rb`
- `test/system/transactions_test.rb`

**Helpers:**
- `app/helpers/entries_helper.rb`
- `app/helpers/transactions_helper.rb`
- `app/helpers/reports_helper.rb`
- `app/helpers/categories_helper.rb`

---

## Modified Files

### Routes (`config/routes.rb`)
Removed routes for:
- budgets
- budget_categories
- categories
- family_merchants
- transfers
- imports (and all nested import routes)
- recurring_transactions
- rules
- transactions/categorize
- transactions/bulk_deletion
- transactions/bulk_update
- transaction category updates
- transfer_match
- mark_as_recurring

Kept routes for:
- accounts, holdings, trades, securities
- sync, valuations
- tags
- chats, family_exports
- provider items (plaid, simplefin, lunchflow, etc.)
- API routes (except categories, merchants, imports)

### Transaction Model (`app/models/transaction.rb`)
- Removed `Transferable`, `Ruleable` from includes
- Removed `belongs_to :category` and `belongs_to :merchant`
- Removed `set_category!` method
- Removed `transfer?` method
- Removed merchant/categorization callbacks
- Simplified `kind` enum to just `standard`

### Family Model (`app/models/family.rb`)
- Removed `AutoTransferMatchable` include
- Removed associations: imports, rules, categories, merchants, budgets, budget_categories, recurring_transactions
- Removed methods: assigned_merchants, available_merchants, auto_categorize_transactions, auto_detect_transaction_merchants, income_statement, investment_contributions_category, tax_advantaged_account_ids

---

## What Was Preserved

### Core Investment Infrastructure
- Accounts (all types: depository, investment, credit_card, loan, property, vehicle, crypto, other)
- Holdings and Holdings calculations
- Securities and Security prices
- Trades
- Valuations
- Sync infrastructure (Sync, SyncJob, provider adapters)
- Provider integrations (Plaid, SimpleFIN, Coinbase, Binance, CoinStats, Lunchflow, Enable Banking, Mercury, SnapTrade, Indexa Capital)
- Balance calculations
- Tags (for organization, not categorization)
- Family exports
- AI Chat functionality
- User management, authentication, MFA
- API infrastructure

---

## Verification Status

- [ ] Rails app boots without errors: `bin/rails runner "puts 'OK'"`
- [ ] Routes file loads: `bin/rails routes`
- [ ] Tests pass (expected: many tests will need updates for removed features)

## Next Steps

1. Fix any remaining model references to deleted features
2. Update tests to remove dependencies on deleted features
3. Run full test suite
4. Clean up any remaining view partials that reference deleted features
5. Verify navigation is simplified
6. Phase 2: Begin building Portfolio Operating System features

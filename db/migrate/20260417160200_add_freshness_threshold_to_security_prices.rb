class AddFreshnessThresholdToSecurityPrices < ActiveRecord::Migration[7.2]
  def change
    add_column :security_prices, :freshness_threshold_hours, :integer, default: 24, null: false
    add_index :security_prices, :freshness_threshold_hours
  end
end

class AddConfidenceToSecurityPrices < ActiveRecord::Migration[7.2]
  def change
    add_column :security_prices, :confidence, :integer, default: 4, null: false
    add_column :security_prices, :source_provider, :string, limit: 255
    add_column :security_prices, :fetched_at, :datetime

    add_index :security_prices, :confidence
    add_index :security_prices, :source_provider
  end
end

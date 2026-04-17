class AddDataQualityFieldsToHoldings < ActiveRecord::Migration[7.2]
  def change
    add_column :holdings, :confidence, :integer, default: 0, null: false
    add_column :holdings, :source_type, :string
    add_column :holdings, :last_verified_at, :datetime
    add_column :holdings, :data_quality_notes, :text

    add_index :holdings, :confidence
    add_index :holdings, :source_type
  end
end

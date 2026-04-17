class AddFieldsToInstrumentMappings < ActiveRecord::Migration[7.2]
  def change
    change_table :instrument_mappings do |t|
      # Standard security identifiers
      t.string :ticker
      t.string :isin
      t.string :cusip
      t.string :sedol

      # Asset classification
      t.string :asset_class
      t.string :sub_asset_class

      # Geographic and sector classification
      t.string :region
      t.string :sector

      # Workflow status - replaces mapped_status
      t.integer :status, null: false, default: 0

      # Flexible metadata storage
      t.jsonb :classification_metadata, default: {}
    end

    # Add indexes for query performance
    add_index :instrument_mappings, :ticker, unique: true
    add_index :instrument_mappings, :status
    add_index :instrument_mappings, :asset_class
    add_index :instrument_mappings, :sub_asset_class
  end
end

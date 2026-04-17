class CreateInstrumentMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :instrument_mappings, id: :uuid do |t|
      t.references :holding, null: false, foreign_key: true, type: :uuid
      t.integer :mapped_status, null: false, default: 0
      t.integer :suggested_sleeve_id
      t.datetime :user_approved_at
      t.integer :mapping_confidence, null: false, default: 0
      t.text :notes
      t.jsonb :suggestion_metadata, default: {}

      t.timestamps
    end

    add_index :instrument_mappings, :holding_id, unique: true
    add_index :instrument_mappings, :mapped_status
    add_index :instrument_mappings, :suggested_sleeve_id
    add_index :instrument_mappings, :mapping_confidence
  end
end

class AddMappingStatusToSecurities < ActiveRecord::Migration[7.2]
  def change
    add_column :securities, :mapping_status, :integer, default: 0, null: false
    add_column :securities, :suggested_mapping_id, :uuid

    add_index :securities, :mapping_status
    add_index :securities, :suggested_mapping_id

    add_foreign_key :securities, :instrument_mappings, column: :suggested_mapping_id, on_delete: :nullify
  end
end

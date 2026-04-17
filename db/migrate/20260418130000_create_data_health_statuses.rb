class CreateDataHealthStatuses < ActiveRecord::Migration[7.2]
  def change
    create_table :data_health_statuses, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :provider_type, null: false
      t.uuid :provider_id, null: false
      t.string :connection_state, null: false, default: "connected"
      t.datetime :last_sync_at
      t.text :error_message
      t.integer :price_freshness_score, default: 100
      t.integer :holdings_freshness_score, default: 100
      t.integer :overall_confidence, default: 100
      t.jsonb :details, default: {}

      t.timestamps
    end

    add_index :data_health_statuses, [:family_id, :provider_type, :provider_id], unique: true, name: "index_data_health_statuses_on_family_provider"
    add_index :data_health_statuses, :family_id
    add_index :data_health_statuses, :connection_state
    add_index :data_health_statuses, :last_sync_at

    add_foreign_key :data_health_statuses, :families, on_delete: :cascade
  end
end

class CreateDecisionLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :decision_logs, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :decision_type, null: false
      t.uuid :actor_id, null: false
      t.string :reference_type, null: false
      t.uuid :reference_id, null: false
      t.text :rationale
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :decision_logs, :family_id
    add_index :decision_logs, :decision_type
    add_index :decision_logs, :actor_id
    add_index :decision_logs, [:reference_type, :reference_id], name: "index_decision_logs_on_reference"
    add_index :decision_logs, [:family_id, :created_at], name: "index_decision_logs_on_family_and_created"
    add_index :decision_logs, :metadata, using: :gin

    add_foreign_key :decision_logs, :families, on_delete: :cascade
    add_foreign_key :decision_logs, :users, column: :actor_id, on_delete: :cascade
  end
end

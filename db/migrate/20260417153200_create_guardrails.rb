class CreateGuardrails < ActiveRecord::Migration[8.0]
  def change
    create_table :guardrails, id: :uuid do |t|
      t.uuid :policy_version_id, null: false
      t.string :name, null: false
      t.string :guardrail_type, null: false
      t.jsonb :configuration, default: {}, null: false
      t.string :severity, null: false, default: "warning"
      t.boolean :enabled, null: false, default: true
      t.text :description

      t.timestamps
    end

    add_index :guardrails, :policy_version_id
    add_index :guardrails, :guardrail_type
    add_index :guardrails, :severity
    add_index :guardrails, :enabled
    add_index :guardrails, [:policy_version_id, :guardrail_type], name: "index_guardrails_on_policy_and_type"
    add_index :guardrails, :configuration, using: :gin

    add_foreign_key :guardrails, :policy_versions, on_delete: :cascade
  end
end

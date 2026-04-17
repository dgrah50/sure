class CreateTopActions < ActiveRecord::Migration[8.0]
  def change
    create_table :top_actions, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :action_type, null: false
      t.integer :priority, null: false, default: 5
      t.string :title, null: false
      t.text :description
      t.jsonb :context_data, default: {}, null: false
      t.datetime :dismissed_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :top_actions, :family_id
    add_index :top_actions, :action_type
    add_index :top_actions, :priority
    add_index :top_actions, :dismissed_at
    add_index :top_actions, [:family_id, :action_type], name: "index_top_actions_on_family_and_type"
    add_index :top_actions, :context_data, using: :gin

    add_foreign_key :top_actions, :families, on_delete: :cascade
  end
end

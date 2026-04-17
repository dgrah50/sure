class CreatePolicyVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :policy_versions, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "draft"
      t.date :effective_date
      t.uuid :created_by_id, null: false
      t.jsonb :configuration, default: {}, null: false

      t.timestamps
    end

    add_index :policy_versions, :family_id
    add_index :policy_versions, :status
    add_index :policy_versions, :effective_date
    add_index :policy_versions, [:family_id, :status], name: "index_policy_versions_on_family_and_status"
    add_index :policy_versions, :configuration, using: :gin
  end
end
class CreateRecommendations < ActiveRecord::Migration[8.0]
  def change
    create_table :recommendations, id: :uuid do |t|
      t.uuid :family_id, null: false
      t.uuid :policy_version_id
      t.string :recommendation_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :title, null: false
      t.text :description
      t.jsonb :details, default: {}, null: false
      t.uuid :approved_by_id
      t.datetime :executed_at

      t.timestamps
    end

    add_index :recommendations, :family_id
    add_index :recommendations, :policy_version_id
    add_index :recommendations, :recommendation_type
    add_index :recommendations, :status
    add_index :recommendations, :approved_by_id
    add_index :recommendations, [:family_id, :status], name: "index_recommendations_on_family_and_status"
    add_index :recommendations, :details, using: :gin

    add_foreign_key :recommendations, :families, on_delete: :cascade
    add_foreign_key :recommendations, :policy_versions, on_delete: :nullify
    add_foreign_key :recommendations, :users, column: :approved_by_id, on_delete: :nullify
  end
end

class CreateSleeves < ActiveRecord::Migration[8.0]
  def change
    create_table :sleeves, id: :uuid do |t|
      t.uuid :policy_version_id, null: false
      t.string :name, null: false
      t.text :description
      t.decimal :target_percentage, precision: 5, scale: 2, null: false
      t.decimal :min_percentage, precision: 5, scale: 2
      t.decimal :max_percentage, precision: 5, scale: 2
      t.integer :sort_order, default: 0, null: false
      t.string :color
      t.uuid :parent_sleeve_id

      t.timestamps
    end

    add_index :sleeves, :policy_version_id
    add_index :sleeves, :parent_sleeve_id
    add_index :sleeves, [:policy_version_id, :sort_order], name: "index_sleeves_on_policy_version_and_sort_order"
    add_index :sleeves, [:parent_sleeve_id, :sort_order], name: "index_sleeves_on_parent_and_sort_order"

    add_foreign_key :sleeves, :policy_versions, on_delete: :cascade
    add_foreign_key :sleeves, :sleeves, column: :parent_sleeve_id, on_delete: :cascade
  end
end

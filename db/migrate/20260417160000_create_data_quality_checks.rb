class CreateDataQualityChecks < ActiveRecord::Migration[7.2]
  def change
    create_table :data_quality_checks do |t|
      t.references :family, null: false, foreign_key: true
      t.string :check_type, null: false
      t.string :status, null: false, default: "pass"
      t.jsonb :details, default: {}
      t.datetime :checked_at, null: false
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :data_quality_checks, :family_id
    add_index :data_quality_checks, :check_type
    add_index :data_quality_checks, :status
    add_index :data_quality_checks, [:family_id, :check_type, :status], name: "index_dqc_on_family_and_type_and_status"
  end
end

class CreateDataQualitySummaries < ActiveRecord::Migration[7.2]
  def change
    create_table :data_quality_summaries do |t|
      t.references :family, null: false, foreign_key: true
      t.integer :overall_score, default: 100
      t.integer :price_freshness_score, default: 100
      t.integer :fx_freshness_score, default: 100
      t.integer :holdings_quality_score, default: 100
      t.datetime :last_sync_at
      t.jsonb :breakdown, default: {}

      t.timestamps
    end

    add_index :data_quality_summaries, :family_id, unique: true
  end
end

class AddStatusTrackingToSyncs < ActiveRecord::Migration[8.0]
  def change
    # Add to syncs table
    add_column :syncs, :status_text, :text
    add_column :syncs, :last_successful_sync_at, :datetime

    # Add to plaid_items table for tracking last successful sync
    add_column :plaid_items, :last_successful_sync_at, :datetime
    add_column :plaid_items, :sync_health_status, :string, default: "healthy", null: false

    # Add to simplefin_items table for tracking last successful sync
    add_column :simplefin_items, :last_successful_sync_at, :datetime
    add_column :simplefin_items, :sync_health_status, :string, default: "healthy", null: false

    # Add indexes for performance
    add_index :syncs, :last_successful_sync_at
    add_index :plaid_items, :sync_health_status
    add_index :simplefin_items, :sync_health_status
  end
end

class AddPolicyToFamilies < ActiveRecord::Migration[8.0]
  def change
    # Add policy_version_id to families (nullable, optional assignment)
    add_column :families, :policy_version_id, :uuid
    add_index :families, :policy_version_id

    # Add foreign key with nullify on delete (policy can be deleted without deleting family)
    add_foreign_key :families, :policy_versions, on_delete: :nullify

    # Add policy_override to accounts for account-specific exceptions
    add_column :accounts, :policy_override, :jsonb, default: {}, null: false
    add_index :accounts, :policy_override, using: :gin
  end
end

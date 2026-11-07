# Electronic signatures on logbook entries (AC 120-78B chapter 2): who signed,
# with which certificate, what they certified, when, how they authenticated,
# and a fingerprint of exactly what was signed. Corrections supersede an entry
# (2.2.8); disabled users can no longer sign (2.2.6.4).
class CreateEntrySignatures < ActiveRecord::Migration[8.1]
  def change
    create_table :entry_signatures do |t|
      t.references :logbook_entry, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :signer_name, null: false
      t.string :signer_email
      t.string :certificate_kind, null: false
      t.string :certificate_number, null: false
      t.text :statement, null: false
      t.datetime :signed_at, null: false
      t.string :content_digest, null: false
      t.text :content_snapshot, null: false
      t.string :seal
      t.string :auth_method, null: false
      t.string :ip_address
      t.string :user_agent
      t.string :origin # set when imported from another system
      t.timestamps
    end
    add_index :entry_signatures, :logbook_entry_id, unique: true, name: "index_entry_signatures_one_per_entry"

    add_reference :logbook_entries, :supersedes, foreign_key: { to_table: :logbook_entries, on_delete: :nullify }
    add_column :logbook_entries, :superseded_at, :datetime
    add_column :users, :disabled_at, :datetime

    create_table :signing_invitations do |t|
      t.references :logbook_entry, null: false, foreign_key: { on_delete: :cascade }
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :email, null: false
      t.string :token_digest, null: false
      t.text :message
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :signing_invitations, :token_digest, unique: true
  end
end

# Draft logbook entries from the API (docs/api.md, "Draft entries"): one
# batch per visit, one unsigned entry per logbook; what the work resolves
# (squawks, inspections) is held until every entry is signed.
class CreateDraftBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :draft_batches do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :api_token, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :external_ref
      t.string :status, null: false, default: "awaiting_signature" # awaiting_signature | completed | withdrawn
      t.string :signer_email
      t.json :held, null: false, default: {} # { "squawks" => [{ "id", "log" }], "inspections" => [{ "id", "log" }] }
      t.datetime :completed_at
      t.timestamps
      t.index :external_ref
    end
    add_reference :logbook_entries, :draft_batch, foreign_key: true
    add_column :logbook_entries, :external_ref, :string
  end
end

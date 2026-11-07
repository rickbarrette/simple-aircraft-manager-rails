# Electronic recordkeeping (AC 120-78B chapter 3):
# - record_versions: every change to a maintenance record, chained by hash per
#   aircraft so removing or altering history shows (3.2.2, 3.2.4)
# - integrity_checks: results of verifying those chains and the signatures
# - backup_runs: the built-in database backups and their verification (3.2.7)
# - app_revisions: which software versions ran when (3.2.6)
# - legacy (paper) records: documents marked as such and the date the
#   electronic records start (3.2.8.10)
class AddRecordsIntegrity < ActiveRecord::Migration[8.1]
  def change
    create_table :record_versions do |t|
      t.integer :aircraft_id, index: true
      t.string :item_type, null: false
      t.integer :item_id, null: false
      t.string :event, null: false
      t.integer :user_id
      t.string :ip_address
      t.text :payload, null: false
      t.string :prev_hash
      t.string :chain_hash, null: false
      t.datetime :created_at, null: false
    end
    add_index :record_versions, %i[item_type item_id]

    create_table :integrity_checks do |t|
      t.boolean :ok, null: false
      t.integer :versions_checked, null: false, default: 0
      t.integer :signatures_checked, null: false, default: 0
      t.json :problems
      t.timestamps
    end

    create_table :backup_runs do |t|
      t.boolean :ok, null: false
      t.string :path
      t.bigint :bytes
      t.text :message
      t.timestamps
    end

    create_table :app_revisions do |t|
      t.string :revision, null: false
      t.datetime :built_at
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end
    add_index :app_revisions, :revision, unique: true

    add_column :documents, :legacy_record, :boolean, null: false, default: false
    add_column :aircraft, :electronic_records_since, :date
  end
end

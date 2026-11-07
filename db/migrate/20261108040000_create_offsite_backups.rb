class CreateOffsiteBackups < ActiveRecord::Migration[8.1]
  def change
    # One row: the Google Drive account the off-site copies go to.
    create_table :offsite_connections do |t|
      t.string :provider, null: false, default: "google_drive"
      t.string :client_id
      t.text :client_secret
      t.text :refresh_token
      t.string :account_email
      t.string :folder_id
      t.string :database_folder_id
      t.string :files_folder_id
      t.references :connected_by, foreign_key: { to_table: :users }
      t.datetime :connected_at
      t.timestamps
    end

    create_table :offsite_runs do |t|
      t.string :kind, null: false # backup | restore_test
      t.boolean :ok, null: false
      t.text :message
      t.bigint :bytes
      t.integer :files_uploaded, null: false, default: 0
      t.json :details
      t.timestamps
    end
    add_index :offsite_runs, [ :kind, :created_at ]

    # Uploaded files already copied off-site (by blob), so each goes once.
    create_table :offsite_files do |t|
      t.references :blob, null: false, index: { unique: true }
      t.string :drive_file_id, null: false
      t.bigint :bytes
      t.timestamps
    end
  end
end

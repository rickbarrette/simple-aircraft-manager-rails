class AddCustomAirportsAndUpdates < ActiveRecord::Migration[8.1]
  def change
    # Airports added by an admin; never touched by OurAirports updates.
    add_column :airports, :custom, :boolean, null: false, default: false
    add_index :airports, :custom

    # History of OurAirports updates (shown on the admin Airports page).
    create_table :airport_updates do |t|
      t.string :status, null: false, default: "queued" # queued | running | done | failed
      t.string :source_url
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :removed_count, null: false, default: 0
      t.text :error
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end

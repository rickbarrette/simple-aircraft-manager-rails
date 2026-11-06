class CreateAirTrailSync < ActiveRecord::Migration[8.1]
  def change
    # ICAO type designator (e.g. C150), used for AirTrail's aircraft type.
    add_column :aircraft, :icao_type, :string

    # One AirTrail account per user; flights sync to their pilot's account.
    create_table :air_trail_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :base_url, null: false
      t.text :api_key, null: false # encrypted
      t.boolean :enabled, null: false, default: true
      t.string :remote_user_id
      t.string :remote_username
      t.string :status          # ok | error
      t.text :last_error
      t.datetime :checked_at
      t.datetime :backfilled_at
      t.timestamps
    end

    # Which AirTrail flight each local flight corresponds to.
    create_table :air_trail_syncs do |t|
      t.references :air_trail_connection, null: false, foreign_key: true
      t.references :flight_log, null: false, foreign_key: true
      t.integer :remote_id
      t.string :payload_digest
      t.string :status, null: false, default: "pending" # pending | synced | error
      t.text :last_error
      t.datetime :synced_at
      t.timestamps
    end
    add_index :air_trail_syncs, [ :air_trail_connection_id, :flight_log_id ], unique: true, name: "idx_air_trail_syncs_unique"

    # Airport code → AirTrail airport id (nil = looked up, not found).
    create_table :air_trail_airports do |t|
      t.references :air_trail_connection, null: false, foreign_key: true
      t.string :code, null: false
      t.integer :remote_id
      t.string :remote_icao
      t.boolean :manual, null: false, default: false
      t.datetime :looked_up_at
      t.timestamps
    end
    add_index :air_trail_airports, [ :air_trail_connection_id, :code ], unique: true, name: "idx_air_trail_airports_unique"
  end
end

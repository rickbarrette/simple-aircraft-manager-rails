class AddClientKeyToFlightLogs < ActiveRecord::Migration[8.1]
  def change
    # A random key from the form, so a flight logged offline and sent again
    # (after a dropped connection) isn't saved twice.
    add_column :flight_logs, :client_key, :string
    add_index :flight_logs, [ :aircraft_id, :client_key ], unique: true
  end
end

# Configurable roles (Role, Permission): the owner/pilot text on each
# aircraft role becomes a link to a role. Owners and pilots keep exactly what
# they could do (Owner has everything; Pilot gets what pilots could do), and
# Mechanic and Viewer are added. The permissions are spelled out here so this
# migration doesn't change if the defaults in code do.
class CreateRoles < ActiveRecord::Migration[8.1]
  BUILT_IN = [
    [ "owner", "Owner", "Everything on the aircraft, including its people and sharing.", [] ],
    [ "mechanic", "Mechanic", "Maintenance records: logbook entries, components, inspections, ADs and squawks.",
      %w[update_hours report_squawks defer_squawks manage_squawks write_notes manage_notes record_consumables
         manage_consumables write_logbook sign_logbook manage_components manage_inspections manage_ads
         manage_major_records manage_weight_balance manage_documents record_oil_analyses manage_oil_analyses
         receive_reminders] ],
    [ "pilot", "Pilot", "Flying: logs flights and hours, reports squawks, adds notes and oil and fuel.",
      %w[log_flights update_hours edit_own_flights report_squawks defer_squawks write_notes record_consumables
         record_oil_analyses sign_logbook] ],
    [ "viewer", "Viewer", "Sees everything on the aircraft and changes nothing.", [] ]
  ].freeze

  def up
    create_table :roles do |t|
      t.string :name, null: false
      t.string :key
      t.string :description
      t.json :permissions, null: false, default: []
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :roles, :key, unique: true
    add_index :roles, :name, unique: true

    now = Time.current
    BUILT_IN.each_with_index do |(key, name, description, permissions), i|
      execute sanitize_sql([ "INSERT INTO roles (name, key, description, permissions, position, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                             name, key, description, permissions.to_json, i, now, now ])
    end

    add_reference :aircraft_roles, :role, foreign_key: true
    execute "UPDATE aircraft_roles SET role_id = (SELECT id FROM roles WHERE roles.key = aircraft_roles.role)"
    execute "UPDATE aircraft_roles SET role_id = (SELECT id FROM roles WHERE key = 'pilot') WHERE role_id IS NULL"
    change_column_null :aircraft_roles, :role_id, false
    remove_column :aircraft_roles, :role
  end

  def down
    add_column :aircraft_roles, :role, :string
    execute "UPDATE aircraft_roles SET role = CASE (SELECT key FROM roles WHERE roles.id = aircraft_roles.role_id) WHEN 'owner' THEN 'owner' ELSE 'pilot' END"
    change_column_null :aircraft_roles, :role, false
    remove_reference :aircraft_roles, :role, foreign_key: true
    drop_table :roles
  end

  private

  def sanitize_sql(args) = ActiveRecord::Base.sanitize_sql_array(args)
end

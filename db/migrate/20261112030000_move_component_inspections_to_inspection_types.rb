# A component's own "Inspect every" (hours / days / months, "Inspection
# critical") only fed the coming-due list, counted from its last service, and
# never affected airworthiness. Inspection types linked to the component do
# all of that properly (records, airworthiness, logbook entries), so each
# setting becomes one: grounding if it was critical, else advisory, with a
# first record at the component's last service so the next due stays the same.
# Components that already had an inspection type linked ignored these fields,
# so they're just dropped.
class MoveComponentInspectionsToInspectionTypes < ActiveRecord::Migration[8.1]
  def up
    rows = select_all(<<~SQL).to_a
      SELECT c.id, c.inspection_hours, c.inspection_days, c.inspection_months, c.inspection_critical,
             c.overhaul_date, c.hours_since_overhaul
      FROM components c
      WHERE c.status <> 'DISPOSED'
        AND (COALESCE(c.inspection_hours, 0) > 0 OR COALESCE(c.inspection_days, 0) > 0 OR COALESCE(c.inspection_months, 0) > 0)
        AND NOT EXISTS (SELECT 1 FROM components_inspection_types ci WHERE ci.component_id = c.id)
    SQL
    [ Component, InspectionType, InspectionRecord ].each(&:reset_column_information)
    rows.each do |row|
      component = Component.find(row["id"])
      critical = ActiveModel::Type::Boolean.new.cast(row["inspection_critical"])
      type = InspectionType.create!(name: "#{component} #{component.model} inspection".squish.first(120), recurring: true,
                                    required: critical, effect: critical ? "grounds" : "advisory",
                                    recurring_hours: row["inspection_hours"].to_i, recurring_days: row["inspection_days"].to_i,
                                    recurring_months: row["inspection_months"].to_i)
      type.components << component
      next unless (date = row["overhaul_date"])
      aircraft = component.aircraft
      hours = aircraft && [ aircraft.current_hours - row["hours_since_overhaul"].to_d, 0 ].max
      InspectionRecord.create!(inspection_type: type, aircraft: aircraft, component: component, date: date, aircraft_hours: hours,
                               notes: "From the component's last service (its former \"Inspect every\" setting).")
    end

    remove_column :components, :inspection_hours
    remove_column :components, :inspection_days
    remove_column :components, :inspection_months
    remove_column :components, :inspection_critical
  end

  def down
    add_column :components, :inspection_hours, :integer
    add_column :components, :inspection_days, :integer
    add_column :components, :inspection_months, :integer
    add_column :components, :inspection_critical, :boolean, default: true, null: false
  end
end

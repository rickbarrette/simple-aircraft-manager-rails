# Standard component types (idempotent).
[
  [ "Engine", false ], [ "Propeller", false ], [ "Magneto", false ], [ "Vacuum Pump", false ],
  [ "Alternator", false ], [ "Starter", false ], [ "ELT", false ], [ "ELT Battery", true ],
  [ "Oil", true ], [ "Oil Filter", true ], [ "Spark Plugs", true ], [ "Air Filter", true ],
  [ "Battery", true ], [ "Transponder", false ], [ "Tires", true ], [ "Brakes", true ]
].each do |name, consumable|
  ComponentType.find_or_create_by!(name: name) { _1.consumable = consumable }
end

# Demo data: `DEMO=1 bin/rails db:seed`
if ENV["DEMO"].present?
  admin = User.find_or_create_by!(email_address: "admin@example.com") do |u|
    u.name = "Demo Admin"
    u.password = "demo-password-123"
    u.admin = true
  end
  pilot = User.find_or_create_by!(email_address: "pilot@example.com") do |u|
    u.name = "Demo Pilot"
    u.password = "demo-password-123"
  end

  Current.session = admin.sessions.first_or_create!(user_agent: "seed", ip_address: "127.0.0.1")

  ac = Aircraft.find_or_create_by!(tail_number: "N12345") do |a|
    a.make = "Cessna"
    a.model = "172N"
    a.serial_number = "17270001"
    a.tach_time = 4210.3
    a.hobbs_time = 5102.8
    a.purchased = Date.new(2019, 6, 1)
  end
  ac.roles.find_or_create_by!(user: admin) { _1.role = "owner" }
  ac.roles.find_or_create_by!(user: pilot) { _1.role = "pilot" }

  type = ->(n) { ComponentType.find_by!(name: n) }
  if ac.components.none?
    engine = ac.components.create!(component_type: type.("Engine"), manufacturer: "Lycoming", model: "O-320-H2AD",
      serial_number: "L-1234-76", status: "IN-USE", date_in_service: Date.new(2012, 3, 1),
      hours_in_service: 1650, hours_since_overhaul: 1650, tbo_hours: 2000, overhaul_date: Date.new(2012, 3, 1))
    ac.components.create!(component_type: type.("Propeller"), manufacturer: "McCauley", model: "1C160/DTM7553",
      status: "IN-USE", date_in_service: Date.new(2015, 1, 1), hours_in_service: 900, hours_since_overhaul: 900,
      tbo_hours: 2000, tbo_critical: true)
    ac.components.create!(component_type: type.("Oil"), parent_component: engine, manufacturer: "Aeroshell",
      model: "W100", status: "IN-USE", date_in_service: 40.days.ago, overhaul_date: 40.days.ago,
      hours_since_overhaul: 44, replacement_hours: 50, replacement_days: 120, replacement_critical: true,
      tbo_critical: false)
    ac.components.create!(component_type: type.("ELT Battery"), manufacturer: "ACK", model: "E-04",
      install_location: "Tailcone", status: "IN-USE", date_in_service: 2.years.ago, overhaul_date: 2.years.ago,
      replacement_days: 730, replacement_critical: true, tbo_critical: false)
  end

  annual = InspectionType.find_or_create_by!(name: "Annual Inspection") { _1.recurring = true; _1.recurring_months = 12 }
  xpdr = InspectionType.find_or_create_by!(name: "Transponder (91.413)") { _1.recurring = true; _1.recurring_months = 24; _1.effect = "no_transponder" }
  [ annual, xpdr ].each { |t| t.aircraft << ac unless t.aircraft.include?(ac) }
  ac.inspection_records.find_or_create_by!(inspection_type: annual) { _1.date = 11.months.ago.to_date; _1.aircraft_hours = 4150 }
  ac.inspection_records.find_or_create_by!(inspection_type: xpdr) { _1.date = 10.months.ago.to_date; _1.aircraft_hours = 4160 }

  ad = AirworthinessDirective.find_or_create_by!(name: "2011-10-09") do |a|
    a.short_description = "Seat rail inspection"
    a.recurring = true
    a.recurring_hours = 100
  end
  ad.aircraft << ac unless ad.aircraft.include?(ac)
  ad.ad_compliances.find_or_create_by!(aircraft: ac) do |c|
    c.date_complied = 11.months.ago.to_date
    c.compliance_notes = "Inspected seat rails and stops IAW AD. No defects."
    c.aircraft_hours_at_compliance = 4150
    c.next_due_at_time = 4250
  end

  ac.squawks.find_or_create_by!(issue_reported: "Left landing light inop") { _1.priority = 2; _1.reported_by = pilot }

  if ac.consumable_records.none?
    hrs = 4150.0
    [ 1, 1, 0.5, 1, 1, 0.5, 1 ].each_with_index do |qt, i|
      hrs += [ 9, 11, 6, 10, 12, 5, 10 ][i]
      ac.consumable_records.create!(record_type: "oil", date: (60 - i * 8).days.ago, quantity_added: qt, flight_hours: hrs)
      ac.consumable_records.create!(record_type: "fuel", date: (60 - i * 8).days.ago,
                                    quantity_added: (8.5 * [ 9, 11, 6, 10, 12, 5, 10 ][i]).round(1), flight_hours: hrs)
    end
  end

  ac.logbook_entries.find_or_create_by!(date: 11.months.ago.to_date, text: "Annual inspection completed IAW 14 CFR 43 App. D. Aircraft found airworthy.") do |e|
    e.entry_type = "INSPECTION"
    e.aircraft_hours_at_entry = 4150
    e.signoff_person = "J. Mechanic A&P/IA 1234567"
  end

  puts "Demo data loaded. Sign in as admin@example.com / demo-password-123 (or pilot@example.com)."
end

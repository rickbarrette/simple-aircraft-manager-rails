module AircraftHelper
  # Tabs on the aircraft pages: [label, path, controller names that highlight it, owner_only]
  def aircraft_tabs(aircraft)
    [
      [ "Overview", aircraft_path(aircraft), %w[aircraft] ],
      [ "Components", aircraft_components_path(aircraft), %w[components] ],
      [ "Squawks", aircraft_squawks_path(aircraft), %w[squawks] ],
      [ "Flights", aircraft_flight_logs_path(aircraft), %w[flight_logs flight_imports air_trail_exports airport_codes] ],
      [ "Oil & Fuel", aircraft_consumable_records_path(aircraft), %w[consumable_records oil_analyses] ],
      [ "Logbook", aircraft_logbook_entries_path(aircraft), %w[logbook_entries] ],
      [ "Inspections", aircraft_inspections_path(aircraft), %w[inspections inspection_types inspection_records] ],
      [ "ADs", aircraft_airworthiness_directives_path(aircraft), %w[airworthiness_directives ad_compliances ad_imports] ],
      [ "Documents", aircraft_documents_path(aircraft), %w[documents document_collections] ],
      [ "Major Records", aircraft_major_records_path(aircraft), %w[major_records] ],
      [ "W&B", aircraft_weight_balance_records_path(aircraft), %w[weight_balance_records loading_setups] ],
      [ "Notes", aircraft_notes_path(aircraft), %w[notes] ],
      [ "Activity", aircraft_events_path(aircraft), %w[events record_versions] ]
    ]
  end

  def component_options(aircraft, include_blank: true)
    opts = aircraft.components.where.not(status: "DISPOSED").includes(:component_type).map { [ _1.to_s, _1.id ] }
    include_blank ? [ [ "— None —", nil ] ] + opts : opts
  end

  def document_options(aircraft)
    [ [ "— None —", nil ] ] + aircraft.documents.ordered.map { [ _1.name, _1.id ] }
  end

  def logbook_options(aircraft)
    [ [ "— None —", nil ] ] + aircraft.logbook_entries.recent_first.limit(300).map { [ "#{_1.date} – #{_1.text.truncate(60)}", _1.id ] }
  end
end

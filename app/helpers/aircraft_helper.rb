module AircraftHelper
  # Tabs on the aircraft pages: [label, path, controller names that highlight it, owner_only]
  def aircraft_tabs(aircraft)
    [
      [ I18n.t("helpers.aircraft.overview"), aircraft_path(aircraft), %w[aircraft] ],
      [ I18n.t("helpers.aircraft.components"), aircraft_components_path(aircraft), %w[components] ],
      [ I18n.t("helpers.aircraft.squawks"), aircraft_squawks_path(aircraft), %w[squawks] ],
      [ I18n.t("helpers.aircraft.flights"), aircraft_flight_logs_path(aircraft), %w[flight_logs flight_imports air_trail_exports airport_codes] ],
      [ I18n.t("helpers.aircraft.oil_fuel"), aircraft_consumable_records_path(aircraft), %w[consumable_records oil_analyses] ],
      [ I18n.t("helpers.aircraft.logbook"), aircraft_logbook_entries_path(aircraft), %w[logbook_entries] ],
      [ I18n.t("helpers.aircraft.inspections"), aircraft_inspections_path(aircraft), %w[inspections inspection_types inspection_records] ],
      [ I18n.t("helpers.aircraft.ads"), aircraft_airworthiness_directives_path(aircraft), %w[airworthiness_directives ad_compliances ad_imports] ],
      [ I18n.t("helpers.aircraft.documents"), aircraft_documents_path(aircraft), %w[documents document_collections] ],
      [ I18n.t("helpers.aircraft.major_records"), aircraft_major_records_path(aircraft), %w[major_records] ],
      [ I18n.t("helpers.aircraft.w_b"), aircraft_weight_balance_records_path(aircraft), %w[weight_balance_records loading_setups] ],
      [ I18n.t("helpers.aircraft.notes"), aircraft_notes_path(aircraft), %w[notes] ],
      [ I18n.t("helpers.aircraft.activity"), aircraft_events_path(aircraft), %w[events record_versions] ]
    ]
  end

  def component_options(aircraft, include_blank: true)
    opts = aircraft.components.where.not(status: "DISPOSED").includes(:component_type).map { [ _1.to_s, _1.id ] }
    include_blank ? [ [ I18n.t("helpers.aircraft.none"), nil ] ] + opts : opts
  end

  def document_options(aircraft)
    [ [ I18n.t("helpers.aircraft.none"), nil ] ] + aircraft.documents.ordered.map { [ _1.name, _1.id ] }
  end

  def logbook_options(aircraft)
    [ [ I18n.t("helpers.aircraft.none"), nil ] ] + aircraft.logbook_entries.recent_first.limit(300).map { [ I18n.t("helpers.aircraft.text", date: _1.date, truncate: (_1.text.truncate(60))), _1.id ] }
  end
end

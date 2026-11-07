require "test_helper"

# Unverified transcriptions, preventive maintenance templates, ICA
# inspections, weight & balance, and watching for newly published ADs.
class GroupFourTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345", make: "Cessna", model: "172N")
  end

  test "transcribed entries stay unverified until an owner checks them" do
    first = @a.logbook_entries.create!(date: Date.new(2020, 1, 1), text: "Oil changed", verified: false, transcription_confidence: "medium")
    second = @a.logbook_entries.create!(date: Date.new(2020, 2, 1), text: "Annual", verified: false)
    @a.logbook_entries.create!(date: Date.new(2020, 3, 1), text: "Typed in")
    sign_in @owner
    get aircraft_logbook_entries_path(@a)
    assert_select ".badge-orange", text: "Unverified", count: 2
    get aircraft_logbook_entries_path(@a, unverified: 1)
    assert_select "tbody tr", 2
    get aircraft_logbook_entry_path(@a, first)
    assert_includes response.body, "Transcribed by Claude (medium confidence) and not yet checked"

    patch verify_aircraft_logbook_entry_path(@a, first)
    assert_redirected_to aircraft_logbook_entry_path(@a, second) # on to the next one
    assert first.reload.verified?
    patch aircraft_logbook_entry_path(@a, second), params: { logbook_entry: { verified: "1" } }
    assert second.reload.verified?

    sign_in @pilot
    patch verify_aircraft_logbook_entry_path(@a, first.tap { _1.update!(verified: false) })
    refute first.reload.verified?
  end

  test "built-in templates are added once, show their reference, and fill in the entry" do
    sign_in @owner
    get new_aircraft_logbook_entry_path(@a)
    count = LogbookTemplate.defaults.size
    assert_equal count, LogbookTemplate.count
    assert_select "select[data-entry-template-target=template] option", count + 1
    assert_select "option[data-log-type=ENG][data-certificate=PILOT][data-entry-type=MAINTENANCE]", text: "Oil and filter change — Part 43 App. A (c)(6), (c)(23)"
    assert_select "option[data-text*='Part 43 Appendix A paragraph (c)(20)']", text: /Cleaning or replacing spark plugs/
    get edit_aircraft_logbook_entry_path(@a, @a.logbook_entries.create!(date: Date.current, text: "x"))
    assert_select "select[data-entry-template-target=template]", 0

    LogbookTemplate.delete_all # deleting them sticks
    get new_aircraft_logbook_entry_path(@a)
    assert_equal 0, LogbookTemplate.count
    assert_select "select[data-entry-template-target=template]", 0
  end

  test "admins add, edit and restore templates" do
    sign_in @owner
    get admin_logbook_templates_path
    assert_redirected_to root_path

    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    get admin_logbook_templates_path
    assert_select "a", text: "+ New Template"
    oil = LogbookTemplate.find_by!(name: "Oil and filter change")
    post admin_logbook_templates_path, params: { logbook_template: { name: "Annual sign-off", reference: "14 CFR 43.11", entry_type: "INSPECTION",
      log_type: "AC", certificate_type: "IA", text: "Annual inspection completed IAW Part 43 Appendix D." } }
    assert_redirected_to admin_logbook_templates_path
    assert_equal [ "INSPECTION", "AC", "IA" ], LogbookTemplate.find_by!(name: "Annual sign-off").then { [ _1.entry_type, _1.log_type, _1.certificate_type ] }
    post admin_logbook_templates_path, params: { logbook_template: { name: "", text: "", entry_type: "NOPE" } }
    assert_response :unprocessable_entity

    patch admin_logbook_template_path(oil), params: { logbook_template: { text: "Changed oil: __ qt of __." } }
    assert_equal "Changed oil: __ qt of __.", oil.reload.text
    delete admin_logbook_template_path(oil)
    post restore_admin_logbook_templates_path
    assert_equal "Restored 1 built-in template.", flash[:notice]
    assert LogbookTemplate.exists?(name: "Oil and filter change")
  end

  test "an STC's ICA becomes a tracked inspection linked from its major record" do
    record = @a.major_records.create!(record_type: "alteration", title: "Engine monitor installed", date_performed: Date.current,
                                      stc_number: "SA02000CH", has_ica: true, ica_notes: "Inspect probes every 100 hrs")
    sign_in @owner
    get aircraft_major_record_path(@a, record)
    assert_select "a[href='#{new_aircraft_inspection_type_path(@a, major_record_id: record.id)}']", text: "Add the ICA's recurring inspection"
    get new_aircraft_inspection_type_path(@a, major_record_id: record.id)
    assert_select "input[name='inspection_type[name]'][value='ICA: Engine monitor installed']"
    assert_includes response.body, "Inspect probes every 100 hrs"

    post aircraft_inspection_types_path(@a), params: { major_record_id: record.id, applies_to_airframe: "1", inspection_type: {
      name: "ICA: Engine monitor installed", recurring: "1", recurring_hours: 100, effect: "grounds" } }
    assert_redirected_to aircraft_major_record_path(@a, record)
    ica = record.reload.ica_inspection_type
    assert_equal [ "ICA: Engine monitor installed", 100 ], [ ica.name, ica.recurring_hours.to_i ]
    assert_includes @a.reload.applicable_inspection_types, ica
    get aircraft_major_record_path(@a, record)
    assert_select "a", text: "ICA: Engine monitor installed"
  end

  test "weight & balance history, loading setup and the calculator" do
    sign_in @pilot
    get aircraft_weight_balance_records_path(@a)
    assert_response :success
    assert_includes response.body, "No weight &amp; balance recorded yet"
    post aircraft_weight_balance_records_path(@a), params: { weight_balance_record: { date: "2026-01-01", empty_weight: 1500, empty_arm: 39 } }
    assert_equal 0, @a.weight_balance_records.count # owners only

    sign_in @owner
    alteration = @a.major_records.create!(record_type: "alteration", title: "Avionics upgrade", date_performed: Date.current)
    post aircraft_weight_balance_records_path(@a), params: { weight_balance_record: {
      date: "2026-01-01", empty_weight: 1500, empty_arm: 39.5, max_gross_weight: 1400 } }
    assert_response :unprocessable_entity
    assert_includes response.body, "must be more than the empty weight"
    post aircraft_weight_balance_records_path(@a), params: { weight_balance_record: {
      date: "2026-01-01", empty_weight: 1500, empty_arm: 39.5, max_gross_weight: 2300, reason: "Avionics upgrade", major_record_id: alteration.id } }
    wb = @a.current_weight_balance
    assert_equal [ 800, 59250, alteration ], [ wb.useful_load.to_i, wb.empty_moment.to_i, wb.major_record ]

    patch aircraft_loading_setup_path(@a), params: { setup: { fuel_lb_per_gal: "6", stations: {
      "0" => { name: "Front seats", arm: "37", max: "" }, "1" => { name: "Fuel", arm: "48", max: "40", fuel: "1" }, "2" => { name: "", arm: "" } },
      envelope: { "0" => { weight: "1500", cg: "35" }, "1" => { weight: "1950", cg: "35" } } } }
    assert_response :unprocessable_entity
    assert_includes response.body, "at least 3 points"

    patch aircraft_loading_setup_path(@a), params: { setup: { fuel_lb_per_gal: "6", stations: {
      "0" => { name: "Front seats", arm: "37", max: "" }, "1" => { name: "Fuel", arm: "48", max: "40", fuel: "1" } },
      envelope: { "0" => { weight: "1500", cg: "35" }, "1" => { weight: "2300", cg: "38.5" }, "2" => { weight: "2300", cg: "47.3" }, "3" => { weight: "1500", cg: "47.3" } } } }
    assert_redirected_to aircraft_weight_balance_records_path(@a)
    setup = @a.reload.loading_setup
    assert_equal [ [ "Front seats", false ], [ "Fuel", true ] ], setup.stations.map { [ _1.name, _1.fuel ] }
    assert_equal 4, setup.envelope.size

    get aircraft_weight_balance_records_path(@a)
    assert_select "[data-controller=wb-calculator][data-wb-calculator-empty-weight-value='1500.0'][data-wb-calculator-max-gross-value='2300.0']"
    assert_select "input[data-wb-calculator-target=station][data-fuel=true][data-arm='48.0']"
    assert_select "input[data-wb-calculator-target=burn]"
    get aircraft_major_record_path(@a, alteration)
    assert_includes response.body, "2026-01-01: 1500.0 lb @ 39.50 in"
    get aircraft_report_path(@a)
    assert_includes response.body, "Empty weight <strong>1,500.0 lb</strong>"
  end

  FR_RESPONSE = { results: [
    { document_number: "2026-17584", title: "Airworthiness Directives; Lycoming Engines", publication_date: "2026-08-28",
      effective_on: "2026-09-14", html_url: "https://www.federalregister.gov/d/2026-17584",
      abstract: "The FAA is adopting a new AD for certain Lycoming O-320 engines. This AD requires replacement of the affected piston pin. The FAA is issuing this AD.",
      docket_ids: [ "Docket No. FAA-2026-8789", "Amendment 39-23454", "AD 2026-17-10" ] },
    { document_number: "2026-11111", title: "Airworthiness Directives; Old One", publication_date: "2026-08-01",
      effective_on: "2026-08-20", html_url: "https://www.federalregister.gov/d/2026-11111", abstract: "Old.", docket_ids: [ "AD 2020-01-01" ] },
    { document_number: "2026-22222", title: "Special Conditions; Something Else", publication_date: "2026-08-02", docket_ids: [] }
  ] }.to_json

  test "newly published ADs are found, tracked or dismissed, and reported weekly" do
    create_component(@a, component_type: component_type("Engine"), model: "O-320-H2AD")
    assert_equal [ "172N", "O-320-H2AD" ], AdWatch.default_terms(@a)
    known = AirworthinessDirective.create!(name: "2020-01-01", short_description: "Already tracked")
    known.aircraft << @a
    stub = stub_request(:get, %r{\Ahttps://www\.federalregister\.gov/api/v1/documents\.json}).to_return(status: 200, body: FR_RESPONSE)

    sign_in @owner
    post check_aircraft_ad_alerts_path(@a)
    assert_redirected_to aircraft_airworthiness_directives_path(@a, anchor: "new-ads")
    assert_requested stub, times: 2 # one search per term
    alert = @a.ad_alerts.sole # already-tracked and non-AD documents skipped
    assert_equal [ "2026-17-10", "39-23454", "new" ], [ alert.ad_number, alert.amendment, alert.status ]
    get aircraft_airworthiness_directives_path(@a)
    assert_includes response.body, "AD 2026-17-10 · Lycoming Engines"
    assert_select "a[href='https://www.federalregister.gov/d/2026-17584']"

    assert_emails 1 do
      WeeklyReminderJob.perform_now
    end
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "New ADs that may apply: 2026-17-10"

    post check_aircraft_ad_alerts_path(@a) # checking again doesn't duplicate
    assert_equal 1, @a.ad_alerts.count

    post track_aircraft_ad_alert_path(@a, alert)
    ad = AirworthinessDirective.find_by!(name: "2026-17-10")
    assert_redirected_to edit_aircraft_airworthiness_directive_path(@a, ad)
    assert_equal [ "Requires replacement of the affected piston pin", Date.new(2026, 9, 14), "39-23454" ],
                 [ ad.short_description, ad.effective_date, ad.docket_number ]
    assert_includes @a.reload.applicable_ads, ad
    assert @a.airworthiness.red? # untracked compliance counts until recorded

    other = @a.ad_alerts.create!(fr_document_number: "X-1", title: "Airworthiness Directives; Other", status: "new")
    post dismiss_aircraft_ad_alert_path(@a, other)
    assert_equal "dismissed", other.reload.status

    patch terms_aircraft_ad_alerts_path(@a), params: { ad_watch_terms: "172, O-320" }
    assert_equal [ "172", "O-320" ], AdWatch.new(@a.reload).terms

    stub_request(:get, %r{federalregister}).to_return(status: 503)
    post check_aircraft_ad_alerts_path(@a)
    assert_match "Couldn't check for new ADs: the Federal Register returned 503", flash[:alert]
    assert_nothing_raised { AdWatchJob.perform_now }

    sign_in @pilot
    post check_aircraft_ad_alerts_path(@a)
    assert_redirected_to aircraft_path(@a)
  end

  test "archives carry weight & balance, the loading setup, the ICA link and verification" do
    ica = InspectionType.create!(name: "ICA: monitor", recurring: true, recurring_hours: 100).tap { _1.aircraft << @a }
    record = @a.major_records.create!(record_type: "alteration", title: "Monitor", date_performed: Date.current, has_ica: true, ica_inspection_type: ica)
    @a.weight_balance_records.create!(date: Date.new(2026, 1, 1), empty_weight: 1500, empty_arm: 39.5, max_gross_weight: 2300, major_record: record)
    @a.update!(loading_stations: { "fuel_lb_per_gal" => 6.0, "stations" => [ { "name" => "Pilot", "arm" => 37.0, "max" => nil, "fuel" => false } ] },
               cg_envelope: [ [ 1500, 35 ], [ 2300, 38.5 ], [ 2300, 47.3 ] ])
    @a.logbook_entries.create!(date: Date.current, text: "Read by Claude", verified: false)
    path = File.join(Dir.mktmpdir, "a.sam.zip")
    AircraftArchive::Exporter.new(@a, source: "sam.example.com").write_to(path)
    copy = AircraftArchive::Importer.new(path, owner: @owner, tail_number: "N54321").run[:aircraft]

    wb = copy.current_weight_balance
    assert_equal [ 1500, "Monitor" ], [ wb.empty_weight.to_i, wb.major_record.title ]
    assert_equal ica, copy.major_records.sole.ica_inspection_type
    assert_equal [ "Pilot" ], copy.loading_setup.stations.map(&:name)
    refute copy.logbook_entries.sole.verified?
  end
end

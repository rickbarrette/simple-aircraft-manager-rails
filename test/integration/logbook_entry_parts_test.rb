require "test_helper"
require "pdf-reader"

# Sub-components on a logbook entry: the oil filter on the engine, with its
# times at the entry.
class LogbookEntryPartsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345", tach_time: 4210.3)
    @engine = create_component(@a, component_type: component_type("Engine"), manufacturer: "Continental", model: "O-470-R",
                                   serial_number: "100001-R", hours_in_service: 2655.9, hours_since_overhaul: 94.7, overhaul_kind: "major")
    @filter = create_component(@a, component_type: component_type("Oil filter"), manufacturer: "Challenger", model: "CP48108C",
                                   serial_number: "10000000", parent_component: @engine, hours_in_service: 120.5, hours_since_overhaul: 20.5)
    @prop = create_component(@a, component_type: component_type("Propeller"), manufacturer: "McCauley", model: "2A34C203")
    @elsewhere = create_component(create_aircraft, component_type: component_type("Oil filter"))
    sign_in @owner
  end

  def entry_params(**extra)
    { date: "2026-08-20", log_type: "ENG", entry_type: "MAINTENANCE", text: "Changed oil; cleaned the filter.", aircraft_hours_at_entry: 4200.3,
      component_id: @engine.id, component_hours_at_entry: 2645.9, component_since_overhaul_at_entry: 84.7 }.merge(extra)
  end

  test "the engine's sub-components are offered and saved with their times" do
    get new_aircraft_logbook_entry_path(@a)
    assert_select "[data-component-times-target=part][data-ancestors='#{@engine.id}'][data-total='120.5'][data-since='20.5'][hidden]" do
      assert_select "input[name='logbook_entry[parts][#{@filter.id}][include]']"
      assert_select "label", text: "Since service"
    end

    post aircraft_logbook_entries_path(@a), params: { logbook_entry: entry_params(parts: {
      @filter.id => { include: "1", hours: "110.5", since: "10.5" },
      @prop.id => { include: "1", hours: "1" },              # not under the engine: ignored
      @elsewhere.id => { include: "1", hours: "1" } }) }     # another aircraft's: ignored
    entry = @a.logbook_entries.sole
    assert_equal [ [ @filter, 110.5, 10.5 ] ], entry.parts.map { [ _1.component, _1.hours_at_entry.to_f, _1.since_overhaul_at_entry.to_f ] }

    get aircraft_logbook_entry_path(@a, entry)
    assert_includes response.body, "110.5 total, 10.5 since service"
    get edit_aircraft_logbook_entry_path(@a, entry)
    assert_select "input[name='logbook_entry[parts][#{@filter.id}][include]'][checked]"
    assert_select "[data-component-times-target=part][data-ancestors='#{@engine.id}']:not([hidden])"

    patch aircraft_logbook_entry_path(@a, entry), params: { logbook_entry: { parts: { @filter.id => { include: "1", hours: "111", since: "11" } } } }
    assert_equal [ 111, 11 ], entry.parts.reload.sole.then { [ _1.hours_at_entry.to_i, _1.since_overhaul_at_entry.to_i ] }
    patch aircraft_logbook_entry_path(@a, entry), params: { logbook_entry: { text: "Changed oil.", parts: { @filter.id => { include: "0" } } } }
    assert_empty entry.parts.reload
  end

  test "a new entry can record a sub-component as serviced or replaced on the Components tab" do
    oil = create_component(@a, component_type: component_type("Oil"), manufacturer: "Phillips", model: "20W50",
                               parent_component: @engine, hours_in_service: 45.0, hours_since_overhaul: 45.0)
    get new_aircraft_logbook_entry_path(@a)
    assert_select "select[name='logbook_entry[parts][#{oil.id}][service]'] option", 3
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: entry_params(parts: {
      @filter.id => { include: "1", hours: "110.5", since: "10.5", service: "serviced" },
      oil.id => { include: "1", hours: "35.0", since: "35.0", service: "replaced" } }) }
    assert_redirected_to aircraft_logbook_entry_path(@a, @a.logbook_entries.last)
    @filter.reload
    oil.reload
    # dated to the entry; the 10 hours flown since the entry carry over
    assert_equal [ Date.new(2026, 8, 20), 10.0, 120.5 ], [ @filter.overhaul_date, @filter.hours_since_overhaul.to_f, @filter.hours_in_service.to_f ]
    assert_equal [ 10.0, 10.0, Date.new(2026, 8, 20) ], [ oil.hours_since_overhaul.to_f, oil.hours_in_service.to_f, oil.date_in_service ]
    assert @a.events.exists?(event_name: "Replaced: #{oil} (logbook entry Aug 20, 2026)")

    entry = @a.logbook_entries.last # editing doesn't offer it again (it would apply twice)
    get edit_aircraft_logbook_entry_path(@a, entry)
    assert_select "select[name='logbook_entry[parts][#{oil.id}][service]']", 0
  end

  test "servicing new oil typed in at 0 hours restarts it from the airframe time flown since the entry" do
    oil = create_component(@a, component_type: component_type("Oil"), manufacturer: "Phillips", model: "20W50",
                               parent_component: @engine, hours_in_service: 36.0, hours_since_overhaul: 36.0)
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: entry_params(aircraft_hours_at_entry: 4210.3, parts: {
      oil.id => { include: "1", hours: "0.0", since: "0.0", service: "serviced" } }) }
    assert_equal [ 0.0, 36.0, Date.new(2026, 8, 20) ], oil.reload.then { [ _1.hours_since_overhaul.to_f, _1.hours_in_service.to_f, _1.overhaul_date ] }
  end

  test "a new entry can complete inspections such as an oil change" do
    oil_change = InspectionType.create!(name: "Oil Change", recurring: true, recurring_hours: 50).tap { _1.aircraft << @a }
    get new_aircraft_logbook_entry_path(@a)
    assert_select "input[name='logbook_entry[inspection_type_ids][]'][value='#{oil_change.id}']"
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: entry_params(inspection_type_ids: [ "", oil_change.id ]) }
    entry = @a.logbook_entries.sole
    record = @a.inspection_records.sole
    assert_equal [ oil_change, entry, Date.new(2026, 8, 20), 4200.3 ], [ record.inspection_type, record.logbook_entry, record.date, record.aircraft_hours.to_f ]
    assert @a.events.exists?(event_name: "Inspection completed: Oil Change (logbook entry Aug 20, 2026)")

    get edit_aircraft_logbook_entry_path(@a, entry) # not offered again on edit (it would record twice)
    assert_select "input[name='logbook_entry[inspection_type_ids][]']", 0
  end

  test "printouts add a line per sub-component; archives carry them" do
    entry = @a.logbook_entries.create!(entry_params.merge(component: @engine))
    entry.parts.create!(component: @filter, hours_at_entry: 110.5, since_overhaul_at_entry: 10.5)
    get aircraft_logbook_print_path(@a, format: :pdf), params: { ids: [ entry.id ], layout: "letter" }
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join(" ").gsub(/\s+/, " ")
    assert_includes text, "Engine: Continental O-470-R S/N 100001-R Engine total time: 2,645.9 SMOH: 84.7"
    assert_includes text, "Oil filter: Challenger CP48108C S/N 10000000 Total time: 110.5 Since service: 10.5"

    path = File.join(Dir.mktmpdir, "a.sam.zip")
    AircraftArchive::Exporter.new(@a, source: "sam.example.com").write_to(path)
    copy = AircraftArchive::Importer.new(path, owner: @owner, tail_number: "N54321").run[:aircraft]
    copied = copy.logbook_entries.sole
    assert_equal [ "Engine", 2645.9 ], [ copied.component.component_type.name, copied.component_hours_at_entry.to_f ]
    assert_equal [ [ "Oil filter", 110.5, 10.5 ] ], copied.parts.map { [ _1.component.component_type.name, _1.hours_at_entry.to_f, _1.since_overhaul_at_entry.to_f ] }
    assert_equal copied.component, copied.parts.sole.component.parent_component
  end
end

require "test_helper"

# Small workflow refinements: readable dates in pickers and the activity log,
# fields that appear when they apply, the next-leg button, grouped component
# limits and the setup checklist for a new aircraft.
class WorkflowPolishTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345", tach_time: 1000)
  end

  test "logbook entry pickers and activity show dates the app's way" do
    entry = @a.logbook_entries.create!(date: Date.new(2025, 12, 14), entry_type: "MAINTENANCE", log_type: "AC", text: "Oil changed")
    sign_in @owner
    get new_aircraft_inspection_record_path(@a)
    assert_select "select[name='inspection_record[logbook_entry_id]'] option[value='#{entry.id}']", text: /\ADec 14, 2025 – Oil changed/
  end

  test "the inspection result appears only for inspection entries" do
    sign_in @owner
    get new_aircraft_logbook_entry_path(@a)
    assert_select "form[data-controller~=show-when] select[name='logbook_entry[entry_type]'][data-show-when-target=source]"
    assert_select "[data-show-when-target=item][data-show-when-value=INSPECTION] select[name='logbook_entry[inspection_result]']"
  end

  test "choosing Ground Aircraft warns what it does" do
    sign_in @pilot
    get new_aircraft_squawk_path(@a)
    assert_select "[data-show-when-target=item][data-show-when-value='0'][hidden]", /This grounds N12345/
    get aircraft_squawks_path(@a)
    assert_select "main a[href='#{new_aircraft_squawk_path(@a)}']", 1 # just the header's Report Squawk
  end

  test "Save and log next leg comes back to the form, starting where the flight ended" do
    sign_in @pilot
    post aircraft_flight_logs_path(@a), params: { next_leg: "1", flight_log: { date: "2026-11-08", tach_out: 1000, tach_in: 1001.2, departure_location: "KOQU", destination_location: "KBID" } }
    assert_redirected_to new_aircraft_flight_log_path(@a, date: "2026-11-08")
    follow_redirect!
    assert_match "The next leg starts where it ended.", flash[:notice]
    assert_select "input[name='flight_log[date]'][value='2026-11-08']"
    assert_select "input[name='flight_log[tach_out]'][value='1001.2']"
    assert_select "input[name='flight_log[departure_location]'][value=KBID]"
  end

  test "a new document is named from its file, and the setup checklist can preset its type" do
    sign_in @owner
    get new_aircraft_document_path(@a, doc_type: "REGISTRATION")
    assert_select "form[data-controller=name-from-file] input[name='document[name]'][data-name-from-file-target=name]"
    assert_select "input[type=file][data-action='name-from-file#fill']"
    assert_select "select[name='document[doc_type]'] option[selected][value=REGISTRATION]"
  end

  test "component limits are grouped and open when in use" do
    sign_in @owner
    get new_aircraft_component_path(@a)
    assert_select "form details:not([open])", 2 # replacement and expiry; overhaul and TBO
    engine = @a.components.create!(component_type: ComponentType.find_or_create_by!(name: "Engine"), manufacturer: "Continental", model: "O-200", date_in_service: Date.current, status: "IN-USE", tbo_hours: 1800)
    get edit_aircraft_component_path(@a, engine)
    assert_select "details[open] input[name='component[tbo_hours]']"
    get aircraft_components_path(@a)
    assert_select "a", text: "Record service"
  end

  test "owners see what's left to set up a new aircraft; pilots don't" do
    sign_in @owner
    get aircraft_path(@a)
    assert_select "[data-controller=dismiss] li", 5
    assert_select "[data-controller=dismiss]", /0 of 5 done/
    @a.components.create!(component_type: ComponentType.find_or_create_by!(name: "Engine"), manufacturer: "Continental", model: "O-200", date_in_service: Date.current, status: "IN-USE")
    get aircraft_path(@a)
    assert_select "[data-controller=dismiss]", /1 of 5 done/
    sign_in @pilot
    get aircraft_path(@a)
    assert_select "[data-controller=dismiss]", 0
  end
end

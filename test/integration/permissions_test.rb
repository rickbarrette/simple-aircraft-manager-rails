require "test_helper"

class PermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @outsider = create_user
    @a = create_aircraft(owner: @owner, pilot: @pilot, tach_time: 1000)
    @engine = create_component(@a, hours_in_service: 100, hours_since_overhaul: 100)
  end

  test "outsider gets 404 for aircraft and nested resources" do
    sign_in @outsider
    get aircraft_path(@a)
    assert_response :not_found
    get aircraft_components_path(@a)
    assert_response :not_found
    patch hours_aircraft_path(@a), params: { tach_time: 2000 }
    assert_response :not_found
    assert_equal 1000, @a.reload.tach_time
  end

  test "fleet only lists accessible aircraft" do
    other = create_aircraft(owner: @outsider, tail_number: "N999ZZ")
    sign_in @pilot
    get root_path
    assert_includes response.body, @a.tail_number
    assert_not_includes response.body, other.tail_number
  end

  test "pilot can update hours, log flights, report squawks, add notes and oil" do
    sign_in @pilot
    patch hours_aircraft_path(@a), params: { tach_time: "1010" }
    assert_equal 1010, @a.reload.tach_time
    assert_equal 110, @engine.reload.hours_in_service

    post aircraft_flight_logs_path(@a), params: { flight_log: { date: Date.current, tach_out: 1010, tach_in: 1011.5, oil_added: 1 } }
    assert_redirected_to aircraft_flight_logs_path(@a)
    assert_equal 1011.5, @a.reload.tach_time
    assert_equal 1, @a.consumable_records.oil.count

    post aircraft_squawks_path(@a), params: { squawk: { priority: 0, issue_reported: "Mag drop" } }
    assert_equal @pilot, @a.squawks.last.reported_by
    assert_equal "RED", @a.reload.airworthiness.status

    post aircraft_notes_path(@a), params: { aircraft_note: { text: "Low on fuel" } }
    assert_equal 1, @a.notes.count

    post aircraft_consumable_records_path(@a), params: { consumable_record: { record_type: "fuel", date: Date.current, quantity_added: 20, flight_hours: 1011.5 } }
    assert_equal 1, @a.consumable_records.fuel.count
  end

  test "pilot cannot edit owner-level data" do
    squawk = @a.squawks.create!(priority: 1, issue_reported: "x")
    sign_in @pilot

    patch resolve_aircraft_squawk_path(@a, squawk)
    assert_not squawk.reload.resolved?

    post aircraft_components_path(@a), params: { component: { component_type_id: component_type.id, manufacturer: "x", model: "y", date_in_service: Date.current } }
    assert_equal 1, @a.components.count

    delete aircraft_component_path(@a, @engine)
    assert Component.exists?(@engine.id)

    patch aircraft_path(@a), params: { aircraft: { tail_number: "HACKED" } }
    assert_not_equal "HACKED", @a.reload.tail_number

    post aircraft_share_tokens_path(@a), params: { share_token: { privilege: "maintenance" } }
    assert_equal 0, @a.share_tokens.count

    get aircraft_aircraft_roles_path(@a)
    assert_response :redirect

    post aircraft_logbook_entries_path(@a), params: { logbook_entry: { date: Date.current, text: "x" } }
    assert_equal 0, @a.logbook_entries.count
  end

  test "owner manages roles with last-owner protection" do
    sign_in @owner
    owner_role = @a.roles.find_by(user: @owner)
    patch aircraft_aircraft_role_path(@a, owner_role), params: { role: "pilot" }
    assert_equal "owner", owner_role.reload.role

    newbie = create_user("newbie@example.com")
    post aircraft_aircraft_roles_path(@a), params: { email_address: "NewBie@example.com ", role: "owner" }
    assert_equal "owner", @a.roles.find_by(user: newbie).role

    delete aircraft_aircraft_role_path(@a, owner_role)
    assert AircraftRole.exists?(owner_role.id), "can't remove self"
  end

  test "owner full workflow: component service, AD compliance, inspection" do
    sign_in @owner
    post reset_service_aircraft_component_path(@a, @engine), params: { reset_in_service: "1" }
    assert_equal 0, @engine.reload.hours_in_service

    post aircraft_airworthiness_directives_path(@a), params: {
      airworthiness_directive: { name: "2024-05-05", short_description: "Muffler", recurring: "1", recurring_hours: 100 },
      applies_to_airframe: "0", component_ids: [ @engine.id ]
    }
    ad = AirworthinessDirective.find_by!(name: "2024-05-05")
    assert_equal [ @engine ], ad.components.to_a
    assert_equal "RED", @a.reload.airworthiness.status

    post aircraft_ad_compliances_path(@a), params: { ad_compliance: { airworthiness_directive_id: ad.id, date_complied: Date.current, compliance_notes: "Inspected", next_due_at_time: 1100 } }
    assert_equal "GREEN", @a.reload.airworthiness.status

    post aircraft_inspection_types_path(@a), params: { inspection_type: { name: "Annual", recurring: "1", recurring_months: 12, required: "1" }, applies_to_airframe: "1" }
    assert_equal "RED", @a.reload.airworthiness.status
    it = InspectionType.find_by!(name: "Annual")
    post aircraft_inspection_records_path(@a), params: { inspection_record: { inspection_type_id: it.id, date: Date.current, aircraft_hours: 1000 } }
    assert_equal "GREEN", @a.reload.airworthiness.status

    delete aircraft_airworthiness_directive_path(@a, ad)
    assert_not @a.reload.applicable_ads.exists?(ad.id)
  end

  test "owner cannot reach another aircraft's records through their own aircraft" do
    other = create_aircraft(owner: @outsider)
    other_engine = create_component(other)
    sign_in @owner
    get aircraft_component_path(@a, other_engine)
    assert_response :not_found
  end
end

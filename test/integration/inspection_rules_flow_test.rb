require "test_helper"

class InspectionRulesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner)
    sign_in @owner
  end

  test "owner sets what overdue means, the overrun allowance and what an inspection also counts as" do
    hundred = InspectionType.create!(name: "100-hour", recurring: true, recurring_hours: 100).tap { _1.aircraft << @a }
    elsewhere = InspectionType.create!(name: "Other aircraft's", recurring: true).tap { _1.aircraft << create_aircraft }
    post aircraft_inspection_types_path(@a), params: { inspection_type: {
      name: "Annual", recurring: "1", recurring_months: 12, effect: "grounds", satisfies_id: hundred.id } }
    annual = InspectionType.find_by!(name: "Annual")
    assert_equal hundred, annual.satisfies

    patch aircraft_inspection_type_path(@a, hundred), params: { inspection_type: { hours_tolerance: "10", satisfies_id: elsewhere.id } }
    assert_equal [ 10, nil ], [ hundred.reload.hours_tolerance.to_i, hundred.satisfies_id ] # other aircraft's types can't be chosen

    get edit_aircraft_inspection_type_path(@a, hundred)
    assert_select "select[name='inspection_type[effect]'] option[value=no_ifr]"
    get aircraft_inspections_path(@a)
    assert_includes response.body, "Also counts as 100-hour"
  end

  test "maintenance clock on the aircraft form; new records default to time in service" do
    patch aircraft_path(@a), params: { aircraft: { time_basis: "hobbs", hobbs_time_offset: 0 } }
    @a.update_columns(hobbs_time: 1234.5)
    assert_equal "hobbs", @a.reload.time_basis
    get new_aircraft_inspection_record_path(@a)
    assert_select "input[name='inspection_record[aircraft_hours]'][value='1234.5']"
    get aircraft_path(@a)
    assert_includes response.body, "pilot in command decides whether the aircraft is airworthy"
    assert_select ".badge-green", text: "Current"
  end
end

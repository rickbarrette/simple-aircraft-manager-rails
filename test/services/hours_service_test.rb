require "test_helper"

class HoursServiceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @aircraft = create_aircraft(owner: @user, tach_time: 1000, hobbs_time: 1200)
    @engine = create_component(@aircraft, hours_in_service: 500, hours_since_overhaul: 300)
    @spare = create_component(@aircraft, status: "SPARE", hours_in_service: 10, hours_since_overhaul: 10)
  end

  test "hours update cascades delta to in-use components only and logs event" do
    HoursService.new(@aircraft, user: @user).update_hours!(tach_time: "1012.5", hobbs_time: "1214")
    assert_equal 1012.5, @aircraft.reload.tach_time
    assert_equal 1214, @aircraft.hobbs_time
    assert_equal 512.5, @engine.reload.hours_in_service
    assert_equal 312.5, @engine.hours_since_overhaul
    assert_equal 10, @spare.reload.hours_in_service
    assert_equal "hours", @aircraft.events.first.category
  end

  test "downward correction clamps component hours at zero" do
    @engine.update!(hours_since_overhaul: 2)
    HoursService.new(@aircraft, user: @user).update_hours!(tach_time: "995")
    assert_equal 0, @engine.reload.hours_since_overhaul
    assert_equal 495, @engine.hours_in_service
  end

  test "flight log increments hours and creates consumable records" do
    flight = @aircraft.flight_logs.new(date: Date.current, tach_out: 1000, tach_in: 1001.8, hobbs_time: 2.1,
                                       oil_added: 1, fuel_added: 20, departure_location: "KPVD", destination_location: "KBID")
    HoursService.new(@aircraft, user: @user).log_flight!(flight)
    assert_equal 1.8, flight.tach_time
    assert_equal 1001.8, @aircraft.reload.tach_time
    assert_equal 1202.1, @aircraft.hobbs_time
    assert_equal 501.8, @engine.reload.hours_in_service
    assert_equal %w[fuel oil], @aircraft.consumable_records.pluck(:record_type).sort
    assert_equal 1001.8, @aircraft.consumable_records.first.flight_hours
    assert_includes @aircraft.events.pluck(:event_name), "Flight logged: 1.8 hrs (KPVD → KBID)"
  end

  test "enforcement blocks flights on red aircraft only when enabled" do
    @aircraft.squawks.create!(priority: 0, issue_reported: "Engine rough")
    HoursService.new(@aircraft).update_hours!(tach_time: 1001) # allowed: enforcement off

    @aircraft.update!(airworthiness_enforcement: true)
    assert_raises(AircraftGroundedError) { HoursService.new(@aircraft).update_hours!(tach_time: 1002) }
    assert_equal 1001, @aircraft.reload.tach_time
  end

  test "component service reset" do
    @engine.reset_service!
    assert_equal 0, @engine.hours_since_overhaul
    assert_equal 500, @engine.hours_in_service
    @engine.reset_service!(reset_in_service: true)
    assert_equal 0, @engine.hours_in_service
    assert_equal Date.current, @engine.date_in_service
  end
end

require "test_helper"

# Correcting a saved flight: everything can be fixed, but its meter readings
# only on the latest flight (the aircraft and components then move by the
# difference). Owners can correct any flight, a pilot the ones they logged.
class FlightEditTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @other = create_user("other@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tach_time: 1000)
    @a.roles.create!(user: @other, role: "pilot")
    @engine = create_component(@a, hours_in_service: 500, hours_since_overhaul: 100)
  end

  def log(user, tach_out:, tach_in:, **extra)
    sign_in user
    post aircraft_flight_logs_path(@a), params: { flight_log: { date: "2026-11-14", tach_out: tach_out, tach_in: tach_in, **extra } }
    @a.flight_logs.order(:id).last
  end

  test "correcting the latest flight's reading moves the aircraft and components by the difference" do
    flight = log(@owner, tach_out: 1000.0, tach_in: 1001.4)
    assert_equal 1001.4, @a.reload.tach_time
    assert_equal 501.4, @engine.reload.hours_in_service

    get edit_aircraft_flight_log_path(@a, flight)
    assert_select "fieldset[disabled]", 0
    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { tach_in: 1001.6, tach_time: 1.4, notes: "Fixed typo" } }
    assert_redirected_to aircraft_flight_log_path(@a, flight)

    flight.reload
    assert_equal 1.6, flight.tach_time # worked out from the readings, not the stale duration
    assert_equal "Fixed typo", flight.notes
    assert_equal 1001.6, @a.reload.tach_time
    assert_equal 501.6, @engine.reload.hours_in_service
    assert_equal 101.6, @engine.hours_since_overhaul
    assert_equal "Flight corrected: Nov 14, 2026", @a.events.where(category: "flight").first.event_name
    assert_match "Tach in", @a.events.where(category: "flight").first.notes
  end

  test "an earlier flight's readings are locked; everything else can be corrected" do
    first = log(@owner, tach_out: 1000.0, tach_in: 1001.4)
    log(@owner, tach_out: 1001.4, tach_in: 1003.0)

    get edit_aircraft_flight_log_path(@a, first)
    assert_select "fieldset[disabled]", 2
    assert_select ".hint a[href=?]", aircraft_path(@a), text: "Update Hours"

    patch aircraft_flight_log_path(@a, first), params: { flight_log: { tach_in: 1009, tach_time: 9, destination_location: "kbos" } }
    first.reload
    assert_equal 1001.4, first.tach_in
    assert_equal "KBOS", first.destination_location
    assert_equal 1003.0, @a.reload.tach_time
    assert_equal 503.0, @engine.reload.hours_in_service
  end

  test "after an hours update the latest flight's readings lock too" do
    flight = log(@owner, tach_out: 1000.0, tach_in: 1001.4)
    patch hours_aircraft_path(@a), params: { tach_time: 1002.0 }
    refute flight.reload.meters_editable?

    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { tach_in: 1001.6 } }
    assert_equal 1001.4, flight.reload.tach_in
    assert_equal 1002.0, @a.reload.tach_time
  end

  test "a pilot can correct the flights they logged, not someone else's" do
    flight = log(@pilot, tach_out: 1000.0, tach_in: 1001.4)
    get aircraft_flight_log_path(@a, flight)
    assert_select "a[href=?]", edit_aircraft_flight_log_path(@a, flight)
    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { notes: "Mine" } }
    assert_equal "Mine", flight.reload.notes

    delete session_path
    sign_in @other
    get aircraft_flight_log_path(@a, flight)
    assert_select "a[href=?]", edit_aircraft_flight_log_path(@a, flight), 0
    get edit_aircraft_flight_log_path(@a, flight)
    assert_redirected_to aircraft_flight_log_path(@a, flight)
    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { notes: "Not mine" } }
    assert_equal "Mine", flight.reload.notes

    delete session_path
    sign_in @owner
    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { notes: "Owner fixed" } }
    assert_equal "Owner fixed", flight.reload.notes
  end

  test "oil and fuel records follow the correction" do
    flight = log(@owner, tach_out: 1000.0, tach_in: 1001.4, fuel_added: 10)
    assert_equal [ 10 ], flight.consumable_records.where(record_type: "fuel").pluck(:quantity_added)

    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { fuel_added: 12, oil_added: 1, oil_added_type: "W100" } }
    assert_equal [ 12 ], flight.consumable_records.where(record_type: "fuel").pluck(:quantity_added)
    assert_equal [ [ 1, "W100" ] ], flight.consumable_records.where(record_type: "oil").pluck(:quantity_added, :consumable_type)

    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { fuel_added: "" } }
    assert_empty flight.consumable_records.where(record_type: "fuel")
    assert_equal 1, flight.consumable_records.where(record_type: "oil").count
  end

  test "an invalid correction shows the form again and changes nothing" do
    flight = log(@owner, tach_out: 1000.0, tach_in: 1001.4)
    patch aircraft_flight_log_path(@a, flight), params: { flight_log: { date: "" } }
    assert_response :unprocessable_entity
    assert_select "fieldset[disabled]", 0 # still the latest flight
    assert_equal Date.new(2026, 11, 14), flight.reload.date
    assert_equal 1001.4, @a.reload.tach_time
  end
end

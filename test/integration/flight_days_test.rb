require "test_helper"

# Flights tab grouped by day: the day's route, totals, and its legs.
class FlightDaysTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
  end

  def leg(date, from, to, tach_out, tach_in, fuel: nil, oil: nil)
    @a.flight_logs.create!(date: date, departure_location: from, destination_location: to, tach_out: tach_out, tach_in: tach_in,
                           fuel_added: fuel, oil_added: oil, user: @owner)
  end

  test "legs are grouped by day with the route chained and totals added up" do
    day = Date.new(2026, 11, 7)
    leg(day, "KBID", "KOQU", 101.0, 101.6, fuel: 10) # logged first but flown second
    leg(day, "KOQU", "KBID", 100.0, 100.7, oil: 1)
    leg(day, "1B9", "KOQU", 102.0, 102.4, fuel: 5.5) # repositioned in between: a gap
    leg(day - 1, "KOQU", "KOQU", 99.0, 99.5)

    days = FlightDay.group(@a.flight_logs.to_a)
    assert_equal [ day, day - 1 ], days.map(&:date)
    d = days.first
    assert_equal "KOQU → KBID → KOQU · 1B9 → KOQU", d.route
    assert_in_delta 1.7, d.tach_time, 0.001
    assert_in_delta 15.5, d.fuel_added, 0.001
    assert_equal 1, d.oil_added
    assert_nil days.last.fuel_added # nothing recorded: shown as "—"

    sign_in @owner
    get aircraft_flight_logs_path(@a)
    assert_select "details.flight-day", 2
    assert_select "details.flight-day summary", text: /Sat Nov 7, 2026.*3 flights.*KOQU → KBID → KOQU · 1B9 → KOQU/m
    assert_select "details.flight-day:first-of-type table tbody tr", 3
    assert_select "details.flight-day:first-of-type a", text: "Leg 1"
  end

  test "legs with missing airports still show" do
    leg(Date.new(2026, 11, 8), nil, "KOQU", 1, 1.5)
    leg(Date.new(2026, 11, 8), nil, nil, 2, 2.5)
    assert_equal "KOQU", FlightDay.group(@a.flight_logs.to_a).first.route
  end
end

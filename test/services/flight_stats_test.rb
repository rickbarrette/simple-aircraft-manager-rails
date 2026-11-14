require "test_helper"

class FlightStatsTest < ActiveSupport::TestCase
  setup do
    @a = create_aircraft(tach_time: 1000)
    @today = Date.new(2026, 11, 5)
  end

  def fly(date, tach, hobbs: nil, from: "KAAA", to: "KBBB", fuel: nil)
    f = @a.flight_logs.create!(date: date, tach_time: tach, hobbs_time: hobbs,
                               departure_location: from, destination_location: to, fuel_added: fuel)
    @a.consumable_records.create!(record_type: "fuel", date: date, quantity_added: fuel, flight_hours: 1000, flight_log: f) if fuel
    f
  end

  def stats = FlightStats.new(@a, today: @today)

  test "periods use Hobbs time, falling back to tach" do
    fly Date.new(2024, 6, 1), 2.0, hobbs: 2.4, fuel: 10
    fly Date.new(2025, 12, 20), 1.0, hobbs: 1.2 # last year, and within past 12 months
    fly Date.new(2026, 3, 1), 1.5             # no Hobbs: counts 1.5
    fly Date.new(2026, 10, 20), 0.8, hobbs: 1.0, from: "kccc ", to: "KAAA", fuel: 12.5

    p30, p12, this_year, last_year, all = stats.periods
    assert_equal [ 1, 1.0, 12.5 ], [ p30.flights, p30.flight, p30.fuel ]
    assert_equal [ 3, 3.7 ], [ p12.flights, p12.flight ]
    assert_equal [ 2, 2.5, 2.3 ], [ this_year.flights, this_year.flight, this_year.tach ]
    assert_equal [ 1, 1.2 ], [ last_year.flights, last_year.flight ]
    assert_equal [ 4, 6.1, 22.5 ], [ all.flights, all.flight, all.fuel ]
    assert_equal Date.new(2024, 6, 1), stats.first_date
  end

  test "totals, airports, monthly series and years" do
    fly Date.new(2026, 9, 1), 1.0, hobbs: 1.2, from: "KOQU", to: "KBID"
    fly Date.new(2026, 9, 1), 0.5, hobbs: 0.6, from: "KBID", to: "koqu"
    fly Date.new(2025, 9, 1), 3.0, hobbs: 3.5, from: "KOQU", to: "KMFD"
    s = stats
    assert_equal 3, s.count
    assert_equal 1.8, s.average_flight
    assert_equal 3.5, s.longest_flight
    assert_equal 3, s.airports_visited
    assert_equal [ "KOQU", 3 ], s.top_airports.first

    months = s.flight_hours_by_month(24)
    assert_equal 24, months.size
    assert_equal 1.8, months["Sep 2026"]
    assert_equal 0.0, months["Oct 2026"]
    assert_equal "Nov 2026", months.keys.last
    assert_equal %w[2026 2025], s.by_year.map(&:label)
    assert_equal 0.2, s.monthly_average_past_year # 1.8 / 12, rounded
  end

  test "no flights" do
    assert_not stats.any?
    assert_nil stats.average_flight
  end
end

require "test_helper"

class AirTrailExportTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @a = create_aircraft(owner: @user, tail_number: "N12345", make: "Cessna", model: "150L")
  end

  def fly(date, from, to, tach:, hobbs: nil, user: @user, notes: nil)
    @a.flight_logs.create!(date: date, departure_location: from, destination_location: to,
                           tach_time: tach, hobbs_time: hobbs, user: user, notes: notes)
  end

  def export(**opts) = AirTrailExport.new(@a, username: "ricky", **opts)

  test "builds AirTrail's import format" do
    fly Date.new(2026, 10, 24), "KLHV", "44N", tach: 1.9, hobbs: 2.0, notes: "Fall colors"
    data = JSON.parse(export(aircraft_type: "c150").to_json)

    assert_equal [ { "id" => "sam-pilot", "username" => "ricky", "displayName" => "ricky" } ], data["users"]
    f = data["flights"].first
    assert_equal "2026-10-24", f["date"]
    assert_equal "day", f["datePrecision"]
    assert_equal({ "code" => "KLHV" }, f["from"])
    assert_equal({ "code" => "44N" }, f["to"])
    assert_equal 7200, f["duration"] # Hobbs 2.0 h in seconds
    assert_nil f["departure"]
    assert_nil f["arrival"]
    assert_nil f["airline"]
    assert_equal({ "name" => "Cessna 150L", "icao" => "C150" }, f["aircraft"])
    assert_equal "N12345", f["aircraftReg"]
    assert_nil f["flightNumber"]
    assert_equal "Tach 1.9 h · Hobbs 2.0 h\nFall colors", f["note"]
    passenger = f["passengers"].first
    assert_equal({ "userId" => "sam-pilot", "guestName" => nil, "seat" => "pilot", "seatNumber" => nil,
                   "seatClass" => nil, "flightReason" => nil, "customFields" => {} }, passenger)
    # every key AirTrail requires (non-optional, nullable) is present
    %w[date from to departure arrival duration airline aircraft flightNumber aircraftReg note passengers].each { assert f.key?(_1), _1 }
  end

  test "repeat legs on the same day and route get stable leg numbers so AirTrail doesn't merge them" do
    d = Date.new(2026, 6, 14)
    fly d, "KOQU", "KBID", tach: 0.4
    fly d, "KBID", "KOQU", tach: 0.4
    fly d, "KOQU", "KBID", tach: 0.5
    fly d + 1, "KOQU", "KBID", tach: 0.5
    numbers = JSON.parse(export.to_json)["flights"].map { _1["flightNumber"] }
    assert_equal [ nil, nil, "#2", nil ], numbers
  end

  test "falls back to tach time; zero-time entries get no duration" do
    fly Date.current, "KOQU", "KOQU", tach: 1.5
    fly Date.current, "KDXR", "KDXR", tach: 0
    durations = JSON.parse(export.to_json)["flights"].map { _1["duration"] }
    assert_equal [ 5400, nil ], durations
  end

  test "skips flights without usable airport codes and can limit to my flights" do
    other = create_user
    fly Date.current, "KOQU", "KBID", tach: 1
    fly Date.current, "", "KBID", tach: 1
    fly Date.current, "Home strip", "KBID", tach: 1
    fly Date.current, "KBID", "KOQU", tach: 1, user: other
    assert_equal [ 2, 2 ], [ export.exportable.size, export.skipped ]
    assert_equal 1, export(only_user: @user).exportable.size
  end

  test "includes GPS tracks and defaults the aircraft type from the aircraft" do
    @a.update!(icao_type: "C150")
    f = fly Date.current, "KOQU", "KBID", tach: 1
    f.track_log.attach(io: File.open(Rails.root.join("test/fixtures/files/tracks/flight.kml")), filename: "flight.kml")
    fly Date.current, "KBID", "KOQU", tach: 1
    flights = JSON.parse(export.to_json)["flights"]
    assert_equal "kml", flights.first.dig("track", "sourceFormat")
    assert_equal 2, flights.first.dig("track", "times").size
    assert_not flights.last.key?("track")
    assert_equal "C150", flights.first.dig("aircraft", "icao")
  end

  test "validates username and aircraft type" do
    fly Date.current, "KOQU", "KBID", tach: 1
    assert export.valid?
    assert_not AirTrailExport.new(@a, username: "ri").valid?
    assert_not AirTrailExport.new(@a, username: "jane pilot").valid?
    assert_not export(aircraft_type: "CESSNA").valid?
    assert_not AirTrailExport.new(create_aircraft, username: "ricky").valid? # no flights
  end
end

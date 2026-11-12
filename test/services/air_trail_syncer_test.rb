require "test_helper"

class AirTrailSyncerTest < ActiveSupport::TestCase
  setup do
    @fake = FakeAirTrail.new(self)
    @user = create_user
    @a = create_aircraft(owner: @user, tail_number: "N12345", icao_type: "C150")
    @connection = AirTrailConnection.create!(user: @user, base_url: FakeAirTrail::BASE, api_key: "at_secret")
    @syncer = AirTrailSyncer.new(@connection)
  end

  def fly(date, from, to, tach: 1.0, hobbs: nil, **attrs)
    # skip callbacks' job enqueueing noise: test adapter just records them
    @a.flight_logs.create!({ date: date, departure_location: from, destination_location: to, tach_time: tach,
                             hobbs_time: hobbs, user: @user }.merge(attrs))
  end

  test "api key is stored encrypted" do
    raw = AirTrailConnection.connection.select_value("select api_key from air_trail_connections where id = #{@connection.id}")
    assert_not_includes raw, "at_secret"
    assert_equal "at_secret", @connection.reload.api_key
  end

  test "push creates the AirTrail flight with resolved ids, pilot seat and track" do
    f = fly(Date.new(2026, 10, 24), "KOQU", "KBID", tach: 0.5, hobbs: 0.6)
    f.track_log.attach(io: File.open(Rails.root.join("test/fixtures/files/tracks/flight.gpx")), filename: "flight.gpx")
    sync = @syncer.push(f)

    assert_equal "synced", sync.status
    body = @fake.flights.fetch(sync.remote_id)
    assert_equal [ "2026-10-24", 101, 102, 7, 2160, "N12345" ],
                 body.values_at("date", "fromId", "toId", "aircraftId", "duration", "aircraftReg")
    assert_equal [ { "userId" => "u-jane", "guestName" => nil, "seat" => "pilot", "seatNumber" => nil,
                     "seatClass" => nil, "flightReason" => nil, "customFields" => {} } ], body["passengers"]
    assert_equal "gpx", body.dig("track", "sourceFormat")
    assert_equal [ -71.412028, 41.597139, 5.2 ], body.dig("track", "coordinates", 0)
    assert_equal "jane", @connection.reload.remote_username
  end

  test "unchanged flights aren't re-sent; changed ones are replaced; deleted-in-AirTrail ones recreated" do
    f = fly(Date.current, "KOQU", "KBID")
    first = @syncer.push(f).remote_id
    puts_before = @fake.requests.count { _1[0] == :put }
    @syncer.push(f)
    assert_equal puts_before, @fake.requests.count { _1[0] == :put }

    f.update!(notes: "Pattern work")
    @syncer.push(f)
    assert_equal "Tach 1.0 h\nPattern work", @fake.flights[first]["note"]

    @fake.flights.delete(first)
    f.update!(notes: "Changed again")
    assert_not_equal first, @syncer.push(f).remote_id
  end

  test "airports are looked up once and cached" do
    fly(Date.current, "KOQU", "KBID")
    fly(Date.current + 1, "KBID", "KOQU")
    @syncer.push(FlightLog.first)
    @syncer.push(FlightLog.last)
    assert_equal 2, @fake.requests.count { _1[1] == "/api/v1/airports" }
  end

  test "unknown airports fail the flight with a clear error, and can be mapped by hand" do
    f = fly(Date.current, "53NH", "KOQU")
    sync = @syncer.push(f)
    assert_equal "error", sync.status
    assert_match "doesn't know airport 53NH", sync.last_error
    assert_equal [ "53NH" ], @connection.unresolved_airport_codes

    assert @syncer.map_airport("53NH", "NH53")
    assert_equal "synced", @syncer.push(f).status
    assert_equal 106, @fake.flights.values.last["fromId"]
  end

  test "logged codes are translated to AirTrail's through the airport database" do
    AirportData.sync!(StringIO.new("ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,iso_region,municipality,gps_code,iata_code,local_code\nK1B9,small_airport,Mansfield Municipal Airport,42,-71,122,US,US-MA,Mansfield,1B9,,1B9\n"))
    sync = @syncer.push(fly(Date.current, "KOQU", "1B9"))
    assert_equal "synced", sync.status
    assert_includes @fake.requests, [ :get, "/api/v1/airports", nil ]
    assert_equal FakeAirTrail::AIRPORTS["K1B9"], @fake.flights[sync.remote_id]["toId"]
  end

  test "same-day repeat legs get leg numbers" do
    d = Date.current
    a = fly(d, "KOQU", "KBID")
    b = fly(d, "KOQU", "KBID")
    @syncer.push(a)
    @syncer.push(b)
    assert_equal [ nil, "#2" ], [ a, b ].map { @fake.flights[_1.air_trail_syncs.first.remote_id]["flightNumber"] }
  end

  test "backfill links flights already in AirTrail (from a file import) instead of duplicating" do
    d = Date.new(2026, 10, 1)
    exact = fly(d, "KOQU", "KBID", hobbs: 1.2)
    repeat = fly(d, "KOQU", "KBID", hobbs: 0.8)
    remapped = fly(d + 1, "53NH", "KPVD", hobbs: 1.3) # hand-mapped to NH53 during the file import
    brand_new = fly(d + 2, "KPVD", "KMFD")
    e1 = @fake.add_existing(date: d.iso8601, from: "KOQU", to: "KBID")
    e2 = @fake.add_existing(date: d.iso8601, from: "KOQU", to: "KBID", flight_number: "#2")
    e3 = @fake.add_existing(date: (d + 1).iso8601, from: "NH53", to: "KPVD", duration: 4680)
    @fake.add_existing(date: d.iso8601, from: "KOQU", to: "KBID", reg: "N54321") # someone else's

    result = @syncer.backfill
    assert_equal({ linked: 3, pushed: 4, failed: 0 }, result)
    assert_equal [ e1, e2, e3 ], [ exact, repeat, remapped ].map { _1.air_trail_syncs.first.remote_id }
    assert_equal 5, @fake.flights.size # 4 existing + brand_new
    assert brand_new.air_trail_syncs.first.remote_id
    assert_equal 106, @connection.airports.find_by(code: "53NH").remote_id # learned from the linked flight
    assert @connection.reload.backfilled_at
  end

  test "bad key marks the connection" do
    @fake.valid_key = "other"
    assert_raises(AirTrailClient::AuthError) { @syncer.push(fly(Date.current, "KOQU", "KBID")) }
    assert_equal "error", @connection.reload.status
    assert_match "Invalid API key", @connection.last_error
  end

  test "client follows pagination and maps errors" do
    3.times { |i| @fake.add_existing(date: "2026-01-0#{i + 1}", from: "KOQU", to: "KBID") }
    client = @connection.client
    ids = []
    client.each_flight { ids << _1["id"] }
    assert_equal 3, ids.size
    err = assert_raises(AirTrailClient::ValidationError) { client.create_flight({}) }
    assert_match "fromId Required", err.message
    assert_nil client.delete_flight(999_999) # 404 on delete is fine
  end
end

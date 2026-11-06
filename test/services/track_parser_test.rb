require "test_helper"

class TrackParserTest < ActiveSupport::TestCase
  def parse(name) = TrackParser.new(file_fixture_path.join("tracks", name).read, filename: name).parse
  def file_fixture_path = Rails.root.join("test/fixtures/files")

  test "GPX: [lon, lat, alt_m] with epoch-second times" do
    t = parse("flight.gpx")
    assert_equal "gpx", t.source_format
    assert_equal [ -71.412028, 41.597139, 5.2 ], t.coordinates.first
    assert_equal 3, t.points
    assert_equal Time.utc(2026, 10, 24, 14).to_i, t.times.first
    assert_equal 2500, t.max_altitude_ft # 762 m
    json = t.as_air_trail_json
    assert_equal %i[coordinates sourceFormat sourceName times], json.keys.sort
    assert_equal "flight.gpx", json[:sourceName]
  end

  test "KML gx:Track and LineString" do
    t = parse("flight.kml")
    assert_equal [ [ -71.412028, 41.597139, 5.2 ], [ -71.5, 41.42, 762.0 ] ], t.coordinates
    assert_equal 2, t.times.size
    line = parse("linestring.kml")
    assert_equal 3, line.points
    assert_nil line.times
  end

  test "CSV: altitude in feet, millisecond timestamps" do
    t = parse("flight.csv")
    assert_equal "csv", t.source_format
    assert_equal [ -71.5, 41.42, 762.0 ], t.coordinates[1] # 2500 ft
    assert_equal 1_793_023_200, t.times.first
  end

  test "sniffs the format when the extension doesn't say" do
    gpx = Rails.root.join("test/fixtures/files/tracks/flight.gpx").read
    assert_equal "gpx", TrackParser.new(gpx, filename: "track.xml").parse.source_format
  end

  test "downsamples huge tracks to AirTrail's limit, keeping the last point" do
    rows = (0..100_200).map { |i| "#{41 + i * 1e-6},-71,1000" }
    t = TrackParser.new("lat,lon,alt\n#{rows.join("\n")}", filename: "big.csv").parse
    assert_operator t.points, :<=, TrackParser::MAX_POINTS + 1
    assert_in_delta 41 + 100_200 * 1e-6, t.coordinates.last[1], 1e-6
  end

  test "rejects unusable tracks" do
    assert_raises(TrackParser::Error) { TrackParser.new("hello", filename: "x.txt").parse }
    assert_raises(TrackParser::Error) { TrackParser.new("lat,lon\n41,-71\n", filename: "one.csv").parse }
    assert_raises(TrackParser::Error) { TrackParser.new("a,b\n1,2\n3,4\n", filename: "x.csv").parse }
  end
end

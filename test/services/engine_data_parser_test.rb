require "test_helper"

class EngineDataParserTest < ActiveSupport::TestCase
  def fixture(name) = Rails.root.join("test/fixtures/files/engine_data", name).read
  def recording = @recording ||= EngineDataParser.new(fixture("cgr30p.csv"), filename: "Flt0144.csv").parse

  test "reads CGR-30P metadata and converts local stamps to UTC" do
    assert_equal "N12345", recording.metadata[:aircraft_id]
    assert_equal "144", recording.metadata[:flight_number]
    assert_equal(-4.hours.to_i, recording.utc_offset)
    assert_equal Time.utc(2025, 7, 14, 12, 11, 45), recording.started_at
    assert_equal Time.utc(2025, 7, 14, 8, 11, 45), recording.local(recording.started_at)
  end

  test "skips the partial row and maps channels by column name" do
    assert_equal 10, recording.samples
    assert_equal 4, recording.cylinders
    assert_equal %i[egt1 egt2 egt3 egt4], recording.egt_keys
    assert_equal 2530.0, recording.max(:rpm)[0] # the "RPM" column, not RPMLEFT
    refute recording.channels.key?(:map) # not on this unit
  end

  test "spreads samples within a second" do
    second_18 = recording.times.select { _1.to_i == Time.utc(2025, 7, 14, 12, 12, 18).to_i }
    assert_equal 2, second_18.size
    assert_in_delta 0.5, second_18.last - second_18.first, 0.001
  end

  test "summary: engine run, hours, peaks" do
    assert_equal Time.utc(2025, 7, 14, 12, 12, 17), recording.engine_start
    assert_equal 519, recording.run_time.to_i # 08:12:17 → 08:20:56
    assert_equal [ 7149.77, 7149.81 ], [ recording.first(:tach), recording.last(:tach) ]
    assert_equal [ 436.9, 437.03 ], [ recording.first(:engine_hours), recording.last(:engine_hours) ]
    assert_equal 0.0, recording.last(:flight_hours)
    assert_equal({ value: 1261.0, cylinder: 4, at: Time.utc(2025, 7, 14, 12, 17, 41) }, recording.hottest(:egt))
    assert_equal 265.0, recording.hottest(:cht)[:value]
    # CHT after shutdown (269 at 08:21:04) doesn't count as a running peak
    assert_operator recording.fuel_burned, :>, 0
  end

  test "integrates fuel flow, not across gaps" do
    r = EngineDataParser.new(<<~CSV).parse
      CGR-30P Flight Data Recording
      Local Time: 2025/07/14 08:00:00
      Zulu Time.: 2025/07/14 12:00:00

      TIME,RPM;***,FLOW;GPH
      08:00:00,2400,10.0
      08:00:01,2400,10.0
      08:00:02,2400,10.0
      08:05:00,2400,10.0
    CSV
    assert_in_delta 10.0 * 2 / 3600, r.fuel_burned, 1e-9
  end

  test "rolls past midnight" do
    r = EngineDataParser.new(<<~CSV).parse
      CGR-30P Flight Data Recording
      Local Time: 2025/07/14 23:59:59

      TIME,RPM;***
      23:59:59,2400
      00:00:00,2400
    CSV
    assert_equal Time.utc(2025, 7, 15), r.ended_at
  end

  test "chart series are thinned and skip blanks" do
    series = recording.chart(:cht1, :rpm, :nope)
    assert_equal [ "CHT 1", "RPM" ], series.map { _1[:name] }
    assert_equal [ recording.started_at, 51.0 ], series.first[:data].first
  end

  test "rejects other files" do
    assert_raises(EngineDataParser::Error) { EngineDataParser.new("lat,lon\n1,2\n").parse }
    assert_raises(EngineDataParser::Error) { EngineDataParser.new("CGR-30P\nLocal Time: 2025/07/14 08:00:00\nTIME,RPM;***\n").parse }
  end

  test "detail series for the chart viewer: ms offsets, compact values, thinned to a limit" do
    full = recording.detail
    assert_equal (recording.started_at.to_r * 1000).round, full[:started_at]
    assert_equal recording.samples, full[:times].size
    assert_equal 0, full[:times].first
    assert_equal ((recording.ended_at - recording.started_at) * 1000).round, full[:times].last
    assert_equal(-4.hours.to_i, full[:utc_offset])
    rpm = full[:channels][:rpm]
    assert_equal [ "RPM", "RPM" ], [ rpm[:label], rpm[:unit] ]
    assert rpm[:values].compact.all?(Integer), "whole numbers are sent as integers"

    thin = recording.detail(max_points: 4)
    assert_operator thin[:times].size, :<=, 4
    assert_equal thin[:times].size, thin[:channels][:cht1][:values].size
  end
end

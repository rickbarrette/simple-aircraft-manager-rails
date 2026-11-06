require "test_helper"

class AirportCodeStandardizerTest < ActiveSupport::TestCase
  setup do
    AirportData.sync!(StringIO.new(<<~CSV))
      ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,iso_region,municipality,gps_code,iata_code,local_code
      KOQU,medium_airport,Quonset State Airport,41.6,-71.4,18,US,US-RI,North Kingstown,KOQU,NCO,OQU
      K1B9,small_airport,Mansfield Municipal Airport,42,-71.2,122,US,US-MA,Mansfield,1B9,,1B9
      K5M3,small_airport,Moultonborough Airport,43.8,-71.4,571,US,US-NH,Moultonborough,,,4MB
      08R,small_airport,Richmond Airport,41.5,-71.6,90,US,US-RI,West Kingston,,,08R
      KZZZ,closed,Old Field,40,-70,0,US,US-RI,Nowhere,,,ZZZ
    CSV
    @a = create_aircraft
    other = create_aircraft
    fly = ->(ac, from, to) { ac.flight_logs.create!(date: Date.current, tach_time: 1, departure_location: from, destination_location: to) }
    fly.(@a, "KOQU", "1B9")
    fly.(@a, "1B9", "4MB")
    fly.(@a, "4MB", "0R8")
    fly.(@a, "08R", "ZZZ")
    fly.(other, "1B9", "KOQU") # another aircraft: untouched
    @s = AirportCodeStandardizer.new(@a)
  end

  test "previews each logged code against the standard code" do
    by_code = @s.changes.index_by(&:from)
    assert_equal %w[1B9 4MB ZZZ], by_code.keys.sort # KOQU and 08R already standard
    assert_equal [ "K1B9", 2, true, nil ], by_code["1B9"].to_h.values_at(:to, :flights, :suggested, :note)
    assert_match "Different identifier", by_code["4MB"].note
    assert_equal false, by_code["ZZZ"].suggested # closed airport: not pre-selected
    assert_equal [ "0R8", 1, "08R" ], @s.unknown.first.to_h.values_at(:code, :flights).push(@s.unknown.first.suggestion&.code)
  end

  test "applies only the chosen codes, to this aircraft only" do
    assert_equal 4, @s.apply!(%w[1B9 4MB]) # 1B9 twice, 4MB twice
    assert_equal [ %w[KOQU K1B9], %w[K1B9 K5M3], %w[K5M3 0R8], %w[08R ZZZ] ],
                 @a.flight_logs.order(:id).pluck(:departure_location, :destination_location)
    assert_equal "1B9", FlightLog.where.not(aircraft: @a).first.departure_location
    assert_match "1B9→K1B9", @a.events.first.notes
    assert_equal %w[ZZZ], AirportCodeStandardizer.new(@a).changes.map(&:from)
  end

  test "fixes unknown codes (typos) to a chosen airport's standard code" do
    assert_equal 1, @s.apply!([], fixes: { "0R8" => "08R", "KOQU" => "1B9", "XXXX" => "1B9" }) # only real unknown codes
    assert_equal %w[4MB 08R], @a.flight_logs.order(:id).third.slice(:departure_location, :destination_location).values
    assert_empty AirportCodeStandardizer.new(@a).unknown
    assert_equal "KOQU", @a.flight_logs.order(:id).first.departure_location
  end

  test "a fix to an airport not in the database is ignored" do
    assert_equal 0, @s.apply!([], fixes: { "0R8" => "NOPE" })
  end
end

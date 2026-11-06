require "test_helper"

class AirportTest < ActiveSupport::TestCase
  setup do
    # Rows shaped like OurAirports data, loaded through the real loader.
    csv = <<~CSV
      ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,iso_region,municipality,gps_code,iata_code,local_code
      KOQU,medium_airport,Quonset State Airport,41.597,-71.412,18,US,US-RI,North Kingstown,KOQU,NCO,OQU
      K1B9,small_airport,Mansfield Municipal Airport,42.0,-71.19,122,US,US-MA,Mansfield,1B9,,1B9
      K5M3,small_airport,Moultonborough Airport,43.76,-71.38,571,US,US-NH,Moultonborough,,,4MB
      KBID,small_airport,Block Island State Airport,41.168,-71.577,108,US,US-RI,Block Island,KBID,BID,BID
      88LL,small_airport,Block Airport,41.9,-89.1,800,US,US-IL,Pearl City,88LL,,88LL
      US-1,closed,Old Quonset Strip,41.5,-71.4,10,US,US-RI,North Kingstown,,,
      XAAA,small_airport,Collision Field,0,0,0,US,US-XX,,KOQU,,
    CSV
    @result = AirportData.sync!(StringIO.new(csv))
  end

  test "loader applies AirTrail's code rule" do
    assert_equal({ created: 7, updated: 0, removed: 0 }, @result)
    assert_equal "K1B9", Airport.find_by(ident: "K1B9").airtrail_code # 3-char GPS code → ident
    assert_equal "KBID", Airport.find_by(ident: "KBID").airtrail_code
    assert_equal "XAAA", Airport.find_by(ident: "XAAA").airtrail_code # GPS code collides with another ident
  end

  test "translates whatever code was logged to AirTrail's" do
    assert_equal "K1B9", Airport.airtrail_code_for("1b9")
    assert_equal "K5M3", Airport.airtrail_code_for("4MB")
    assert_equal "KBID", Airport.airtrail_code_for("BID")
    assert_equal "KOQU", Airport.airtrail_code_for("KOQU") # not the colliding XAAA
    assert_nil Airport.airtrail_code_for("ZZZZ")
    assert_equal "K1B9", Airport.lookup("1B9").code # standard (AirTrail/ICAO-style) code
    assert_equal [ "1B9" ], Airport.lookup("1B9").other_codes
  end

  test "search: exact codes first, then prefixes, then names; closed last; familiar airports first" do
    assert_equal "KOQU", Airport.search("koqu").first.code
    assert_equal "KOQU", Airport.search("quonset").first.code
    assert_equal "Old Quonset Strip", Airport.search("quonset").last.name
    assert_equal [ "88LL", "KBID" ], Airport.search("block").map(&:code)
    assert_equal [ "KBID", "88LL" ], Airport.search("block", prefer: [ "KBID" ]).map(&:code)
    assert_empty Airport.search("k")
    assert_equal({ code: "K1B9", name: "Mansfield Municipal Airport", place: "Mansfield, MA", airtrail_code: "K1B9", kind: nil, aka: [ "1B9" ] },
                 Airport.lookup("1B9").as_suggestion)
  end

  HEADER = "ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,iso_region,municipality,gps_code,iata_code,local_code\n".freeze

  test "updates in place like AirTrail: adds, changes, removes; ids stay stable" do
    koqu_id = Airport.find_by(ident: "KOQU").id
    csv = HEADER + <<~CSV
      KOQU,medium_airport,Quonset State Airport (renamed),41.597,-71.412,18,US,US-RI,North Kingstown,KOQU,NCO,OQU
      K1B9,small_airport,Mansfield Municipal Airport,42.0,-71.19,122,US,US-MA,Mansfield,1B9,,1B9
      KNEW,small_airport,New Field,40,-70,5,US,US-RI,Newtown,KNEW,,NEW
    CSV
    assert_equal({ created: 1, updated: 1, removed: 5 }, AirportData.sync!(StringIO.new(csv)))
    assert_equal koqu_id, Airport.find_by(ident: "KOQU").id
    assert_equal "Quonset State Airport (renamed)", Airport.find_by(ident: "KOQU").name
    assert_equal({ created: 0, updated: 0, removed: 0 }, AirportData.sync!(StringIO.new(csv))) # idempotent
  end

  test "custom airports survive updates and win over a source airport with the same code" do
    Airport.create!(custom: true, ident: "0r8", name: "My Strip", kind: "small_airport")
    Airport.create!(custom: true, ident: "KNEW", name: "Our name for it", kind: "small_airport")
    csv = HEADER + "KNEW,small_airport,New Field,40,-70,5,US,US-RI,Newtown,KNEW,,NEW\n"
    AirportData.sync!(StringIO.new(csv))
    assert_equal "My Strip", Airport.find_by(ident: "0R8").name
    assert_equal "0R8", Airport.lookup("0r8").airtrail_code
    assert_equal "Our name for it", Airport.find_by(ident: "KNEW").name
    assert_equal 1, Airport.where(ident: "KNEW").count
  end
end

require "test_helper"

class AirworthinessTest < ActiveSupport::TestCase
  setup do
    @aircraft = create_aircraft(tach_time: 1000)
  end

  test "clean aircraft is green" do
    assert_equal "GREEN", @aircraft.airworthiness.status
  end

  test "unresolved priority-0 squawk grounds aircraft" do
    @aircraft.squawks.create!(priority: 0, issue_reported: "Flat tire")
    assert_equal "RED", Airworthiness.new(@aircraft).call.status
  end

  test "lower-priority squawk does not affect status" do
    @aircraft.squawks.create!(priority: 1, issue_reported: "Light out")
    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status
  end

  test "required inspection never completed is red" do
    InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12).aircraft << @aircraft
    result = Airworthiness.new(@aircraft).call
    assert_equal "RED", result.status
    assert_match "Never Completed", result.issues.first.title
  end

  test "annual due at end of month, orange within 30 days" do
    type = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12)
    type.aircraft << @aircraft
    @aircraft.inspection_records.create!(inspection_type: type, date: Date.new(2025, 6, 10), aircraft_hours: 900)

    assert_equal "GREEN", Airworthiness.new(@aircraft, today: Date.new(2026, 5, 30)).call.status
    assert_equal "ORANGE", Airworthiness.new(@aircraft, today: Date.new(2026, 6, 15)).call.status
    assert_equal "ORANGE", Airworthiness.new(@aircraft, today: Date.new(2026, 6, 30)).call.status
    assert_equal "RED", Airworthiness.new(@aircraft, today: Date.new(2026, 7, 1)).call.status
  end

  test "hour-based inspection uses current hours minus offset" do
    type = InspectionType.create!(name: "100 hr", recurring: true, recurring_hours: 100)
    type.aircraft << @aircraft
    @aircraft.inspection_records.create!(inspection_type: type, date: Date.current, aircraft_hours: 950)

    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status   # 50 hrs since
    @aircraft.update!(tach_time: 1045)
    assert_equal "ORANGE", Airworthiness.new(@aircraft).call.status  # 95 since, within 10
    @aircraft.update!(tach_time: 1050)
    assert_equal "RED", Airworthiness.new(@aircraft).call.status     # 100 since
    @aircraft.update!(tach_time_offset: 10)
    assert_equal "ORANGE", Airworthiness.new(@aircraft).call.status  # offset → 90 since
  end

  test "AD without compliance is red; hour-based due soon is orange; permanent is green" do
    ad = AirworthinessDirective.create!(name: "2020-01-01", short_description: "Check thing")
    ad.aircraft << @aircraft
    assert_equal "RED", Airworthiness.new(@aircraft).call.status

    c = ad.ad_compliances.create!(aircraft: @aircraft, date_complied: Date.current, compliance_notes: "Done",
                                  next_due_at_time: 1005)
    assert_equal "ORANGE", Airworthiness.new(@aircraft).call.status
    c.update!(permanent: true)
    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status
  end

  test "conditional and non-mandatory ADs never affect status" do
    AirworthinessDirective.create!(name: "C", short_description: "x", compliance_type: "conditional").aircraft << @aircraft
    AirworthinessDirective.create!(name: "S", short_description: "x", bulletin_type: "sb", mandatory: false).aircraft << @aircraft
    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status
  end

  test "AD applied via component counts for the aircraft" do
    engine = create_component(@aircraft)
    AirworthinessDirective.create!(name: "ENG", short_description: "x").components << engine
    assert_equal "RED", Airworthiness.new(@aircraft).call.status
  end

  test "replacement-critical component overdue by hours or days" do
    oil = create_component(@aircraft, component_type: component_type("Oil"), replacement_critical: true,
                           replacement_hours: 50, hours_since_overhaul: 45, overhaul_date: Date.current)
    assert_equal "ORANGE", Airworthiness.new(@aircraft).call.status
    oil.update!(hours_since_overhaul: 50)
    assert_equal "RED", Airworthiness.new(@aircraft).call.status
    oil.update!(hours_since_overhaul: 0, replacement_days: 120, overhaul_date: 121.days.ago.to_date)
    assert_equal "RED", Airworthiness.new(@aircraft).call.status
  end

  test "a life limit counted from installation ignores servicing" do
    filter = create_component(@aircraft, component_type: component_type("Oil filter"), replacement_critical: true, replacement_hours: 1250,
                              hours_in_service: 1250, hours_since_overhaul: 10, date_in_service: Date.current, overhaul_date: Date.current)
    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status # counted from the last cleaning: 1240 hrs left
    filter.update!(replacement_from_install: true)
    assert_equal [ 0, Date.current ], [ filter.hours_to_replacement, filter.replacement_counted_from ]
    assert_equal "RED", Airworthiness.new(@aircraft).call.status
    filter.update!(hours_in_service: 0, replacement_hours: nil, replacement_months: 60, date_in_service: 61.months.ago.to_date)
    assert_equal "RED", Airworthiness.new(@aircraft).call.status # 5 years since installed, though cleaned today
  end

  test "spare components are ignored" do
    create_component(@aircraft, status: "SPARE", replacement_critical: true, replacement_hours: 10, hours_since_overhaul: 50)
    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status
  end
end

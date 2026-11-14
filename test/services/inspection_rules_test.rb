require "test_helper"

# Part 91 inspection rules: what an overdue inspection means, the annual
# counting as the 100-hour, the 100-hour's 10-hour allowance, and which clock
# is time in service.
class InspectionRulesTest < ActiveSupport::TestCase
  setup { @a = create_aircraft(tach_time: 1150) }

  def type(name, **attrs)
    InspectionType.create!({ name: name, recurring: true }.merge(attrs)).tap { _1.aircraft << @a }
  end

  def done(type, date, hours = nil) = @a.inspection_records.create!(inspection_type: type, date: date, aircraft_hours: hours)

  test "overdue transponder or pitot-static checks limit the aircraft instead of grounding it" do
    xpdr = type("Transponder (91.413)", recurring_months: 24, effect: "no_transponder")
    done(xpdr, 3.years.ago.to_date)
    aw = @a.reload.airworthiness
    assert aw.limited?
    assert_not aw.red?
    assert_equal "No transponder", aw.label
    assert_equal "LIMITED", aw.issues.sole.severity

    pitot = type("Pitot-static (91.411)", recurring_months: 24, effect: "no_ifr")
    done(pitot, 3.years.ago.to_date)
    assert_equal "No transponder · VFR only", @a.reload.airworthiness.label

    @a.update!(airworthiness_enforcement: true) # flying isn't blocked by limitations
    assert_nothing_raised { HoursService.new(@a).enforce_airworthiness! }

    annual = type("Annual", recurring_months: 12)
    done(annual, 13.months.ago.to_date)
    aw = @a.reload.airworthiness
    assert_equal [ "RED", "Grounded" ], [ aw.status, aw.label ]
    assert_raises(AircraftGroundedError) { HoursService.new(@a).enforce_airworthiness! }
  end

  test "advisory inspections never affect the status; a fresh aircraft reads Current" do
    done(type("Wash", recurring_days: 30, effect: "advisory"), 1.year.ago.to_date)
    aw = @a.reload.airworthiness
    assert_equal [ "GREEN", "Current" ], [ aw.status, aw.label ]
    refute InspectionType.last.required? # kept in step for archives
  end

  test "an annual also counts as the 100-hour" do
    hundred = type("100-hour", recurring_hours: 100, hours_tolerance: 10)
    annual = type("Annual", recurring_months: 12, satisfies: hundred)
    done(hundred, 4.months.ago.to_date, 1000)
    assert_equal 1100, Compliance.inspection_status(hundred, hundred.records_for(@a), @a.current_hours).next_due_hours
    assert @a.reload.airworthiness.red? # 150 hrs since the 100-hour

    done(annual, 1.month.ago.to_date, 1090)
    row = Compliance.inspection_rows(@a).find { _1.type == hundred }
    assert_equal [ "compliant", 1190 ], [ row.status, row.next_due_hours ]
    assert_equal annual, row.latest.inspection_type
    refute @a.reload.airworthiness.red?
  end

  test "the 100-hour's 10-hour allowance counts toward the next interval; early gets no credit" do
    hundred = type("100-hour", recurring_hours: 100, hours_tolerance: 10)
    done(hundred, 300.days.ago.to_date, 1000) # due at 1100
    next_due = ->(records) { Compliance.next_due_hours(hundred, records) }

    late = done(hundred, 200.days.ago.to_date, 1105)
    assert_equal 1200, next_due.(hundred.records_for(@a)) # counted from 1100, not 1105
    late.update!(aircraft_hours: 1115)                    # past the allowance: from when done
    assert_equal 1215, next_due.(hundred.records_for(@a))
    late.update!(aircraft_hours: 1080)                    # early: from when done
    assert_equal 1180, next_due.(hundred.records_for(@a))
  end

  test "overdue within the allowance says what 91.409(b) allows" do
    hundred = type("100-hour", recurring_hours: 100, hours_tolerance: 10)
    done(hundred, 100.days.ago.to_date, 1045) # due 1145, now 1150
    issue = @a.reload.airworthiness.issues.sole
    assert_match "up to 10 hrs past due only to reach a place where it can be done", issue.description
    @a.update!(tach_time: 1170)
    assert_equal "Inspection overdue.", @a.reload.airworthiness.issues.sole.description
  end

  test "Hobbs as the maintenance clock" do
    @a.update!(hobbs_time: 1300, hobbs_time_offset: 20, time_basis: "hobbs")
    assert_equal 1280, @a.current_hours
    engine = create_component(@a, hours_since_overhaul: 500, hours_in_service: 500)
    HoursService.new(@a).log_flight!(@a.flight_logs.new(date: Date.current, tach_time: 1.0, hobbs_time: 1.3))
    assert_equal 501.3, engine.reload.hours_since_overhaul.to_f
    assert_equal [ 1151, 1301.3 ], [ @a.reload.tach_time.to_f, @a.hobbs_time.to_f ]

    HoursService.new(@a).update_hours!(tach_time: 1152, hobbs_time: 1302.5)
    assert_equal 502.5, engine.reload.hours_since_overhaul.to_f
  end
end

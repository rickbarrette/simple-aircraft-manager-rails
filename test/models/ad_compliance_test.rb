require "test_helper"

class AdComplianceTest < ActiveSupport::TestCase
  setup do
    @aircraft = create_aircraft(tach_time: 7290.3)
    @ad = AirworthinessDirective.create!(name: "2011-10-09", short_description: "Seat rails")
    @ad.aircraft << @aircraft
  end

  def comply(**attrs)
    @ad.ad_compliances.new({ aircraft: @aircraft, date_complied: Date.current, compliance_notes: "Done" }.merge(attrs))
  end

  test "rejects an interval entered as the next-due reading" do
    c = comply(aircraft_hours_at_compliance: 7243.4, next_due_at_time: 100)
    assert_not c.valid?
    assert_match "enter 7343.4, not 100", c.errors[:next_due_at_time].first
  end

  test "falls back to current tach when compliance hours are blank" do
    assert_not comply(next_due_at_time: 100).valid?
    assert comply(next_due_at_time: 7390.3).valid?
  end

  test "accepts a future reading, zero, or permanent" do
    assert comply(aircraft_hours_at_compliance: 7243.4, next_due_at_time: 7343.4).valid?
    assert comply(aircraft_hours_at_compliance: 7243.4, next_due_at_time: 0).valid?
    assert comply(aircraft_hours_at_compliance: 7243.4, next_due_at_time: 100, permanent: true).valid?
  end

  test "a correct reading makes the aircraft airworthy again" do
    comply(aircraft_hours_at_compliance: 7243.4, next_due_at_time: 7343.4).save!
    assert_equal "GREEN", Airworthiness.new(@aircraft).call.status
  end

  test "next due is calculated from the AD's hour recurrence when left blank" do
    @ad.update!(recurring: true, recurring_hours: 100)
    c = comply(aircraft_hours_at_compliance: 7243.4)
    c.save!
    assert_equal BigDecimal("7343.4"), c.next_due_at_time
  end

  test "a typed-in reading wins over the calculation, permanent never gets one" do
    @ad.update!(recurring: true, recurring_hours: 100)
    assert_equal BigDecimal("7300"), comply(aircraft_hours_at_compliance: 7243.4, next_due_at_time: 7300).tap(&:save!).next_due_at_time
    assert_equal 0, comply(aircraft_hours_at_compliance: 7243.4, permanent: true).tap(&:save!).next_due_at_time
  end

  test "one-time AD gets no hour-based next due" do
    assert_equal 0, comply(aircraft_hours_at_compliance: 7243.4).tap(&:save!).next_due_at_time
  end
end

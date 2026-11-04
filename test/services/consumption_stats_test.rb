require "test_helper"

class ConsumptionStatsTest < ActiveSupport::TestCase
  test "oil hrs/qt average excludes IQR outliers and excluded records" do
    a = create_aircraft
    a.consumable_records.create!(record_type: "oil", date: Date.current, quantity_added: 1, flight_hours: 100)
    hours = 100.0
    # interval values (hrs/qt): 10, 11, 9, 10, 1 (outlier), 12, 10 (manually excluded)
    [ [ 10, false ], [ 11, false ], [ 9, false ], [ 10, false ], [ 1, false ], [ 12, false ], [ 10, true ] ].each do |dh, excl|
      hours += dh
      a.consumable_records.create!(record_type: "oil", date: Date.current, quantity_added: 1, flight_hours: hours,
                                   excluded_from_averages: excl)
    end
    stats = ConsumptionStats.new(a, "oil")
    assert_equal 7, stats.points.size
    assert_equal 10.4, stats.average # (10+11+9+10+12)/5
  end

  test "zero spread disables outlier filtering (matches original)" do
    a = create_aircraft
    [ 100, 110, 120, 130, 131, 141 ].each do |h|
      a.consumable_records.create!(record_type: "oil", date: Date.current, quantity_added: 1, flight_hours: h)
    end
    assert_equal 8.2, ConsumptionStats.new(a, "oil").average
  end

  test "fuel gal/hr" do
    a = create_aircraft
    a.consumable_records.create!(record_type: "fuel", date: Date.current, quantity_added: 40, flight_hours: 100)
    a.consumable_records.create!(record_type: "fuel", date: Date.current, quantity_added: 17, flight_hours: 102)
    assert_equal 8.5, ConsumptionStats.new(a, "fuel").average
  end
end

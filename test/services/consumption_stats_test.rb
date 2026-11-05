require "test_helper"

class ConsumptionStatsTest < ActiveSupport::TestCase
  setup { @a = create_aircraft }

  def add(type, hours, qty, excluded: false)
    @a.consumable_records.create!(record_type: type, date: Date.current, flight_hours: hours,
                                  quantity_added: qty, excluded_from_averages: excluded)
  end

  test "partial fills and top-offs don't spike fuel burn" do
    add "fuel", 100, 20   # baseline fill
    add "fuel", 105, 20
    add "fuel", 105.2, 10 # top-off 0.2 h later: per-fill math would say 50 gal/hr
    add "fuel", 110, 30
    stats = ConsumptionStats.new(@a, "fuel")
    assert_equal [ [ 110.0, 6.0 ] ], stats.points # 60 gal over 10 h
    assert_equal 6.0, stats.recent
    assert_equal 6.0, stats.lifetime
  end

  test "oil hrs/qt rolling window, oil changes excluded" do
    add "oil", 0, 6
    add "oil", 10, 1
    add "oil", 20, 6, excluded: true # oil change
    add "oil", 25, 1
    add "oil", 30, 1
    add "oil", 40, 1
    stats = ConsumptionStats.new(@a, "oil")
    assert_equal 10.0, stats.lifetime # 40 h / 4 qt counted
    assert_equal [ 25.0, 12.5 ], stats.points.first # first 25 h window: 25 h / 2 qt (oil change not counted)
    assert_equal 10.0, stats.latest                 # window 10→40 h: 30 h / 3 qt
  end

  test "recent window looks back about 50 fuel hours" do
    add "fuel", 0, 10
    add "fuel", 100, 1000 # old era: 10 gal/hr
    add "fuel", 150, 300  # recent: 6 gal/hr
    stats = ConsumptionStats.new(@a, "fuel")
    assert_equal 6.0, stats.recent
    assert_equal 8.7, stats.lifetime # 1300 / 150
  end

  test "too little history" do
    add "oil", 10, 1
    stats = ConsumptionStats.new(@a, "oil")
    assert_nil stats.recent
    assert_empty stats.points
  end
end

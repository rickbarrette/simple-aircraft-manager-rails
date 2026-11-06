require "test_helper"

class OilAnalysisTest < ActiveSupport::TestCase
  setup { @a = create_aircraft }

  def analysis(**attrs) = @a.oil_analyses.new({ sample_date: Date.current }.merge(attrs))

  test "flags readings well above the lab average" do
    a = analysis(iron: 60, iron_avg: 35, copper: 10, copper_avg: 20, silicon: 20, silicon_avg: 13.3, tin: 5)
    assert a.flagged?("iron")
    refute a.flagged?("copper")
    assert a.flagged?("silicon") # exactly 1.5×
    refute a.flagged?("tin")     # no average to compare
    assert_equal %w[iron silicon], a.flagged_elements
  end

  test "validates status, non-negative results, and engine on this aircraft" do
    assert analysis.valid?
    refute analysis(status: "bad").valid?
    refute analysis(iron: -1).valid?
    other_engine = create_component(create_aircraft)
    a = analysis(component: other_engine)
    refute a.valid?
    assert_includes a.errors[:component], "must be on this aircraft"
  end
end

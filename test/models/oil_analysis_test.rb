require "test_helper"

class OilAnalysisTest < ActiveSupport::TestCase
  setup { @a = create_aircraft }

  def analysis(**attrs) = @a.oil_analyses.new({ sample_date: Date.current }.merge(attrs))

  test "flags readings well above the lab average" do
    a = analysis(elements: { iron: 60, copper: 10, silicon: 20, tin: 5 },
                 element_averages: { iron: 35, copper: 20, silicon: 13.3 })
    assert a.flagged?("iron")
    refute a.flagged?("copper")
    assert a.flagged?("silicon") # exactly 1.5×
    refute a.flagged?("tin")     # no average to compare
    assert_equal %w[iron silicon], a.flagged_elements
  end

  test "results from a form: blanks dropped, numbers kept, unknown keys ignored" do
    a = analysis(elements: { "iron" => "30.5", "copper" => "", "unobtainium" => "9" },
                 oil_properties: { "flashpoint_f" => "445", "water_percent" => "0" })
    assert a.valid?
    assert_equal({ "iron" => 30.5 }, a.elements)
    assert_equal({ "flashpoint_f" => 445.0, "water_percent" => 0.0 }, a.oil_properties)
    a.save!
    assert_equal({ "iron" => 30.5 }, a.reload.elements)
  end

  test "validates status, non-negative numeric results, and engine on this aircraft" do
    assert analysis.valid?
    assert analysis(status: "").valid? # not rated
    assert analysis(status: "monitor").valid?
    refute analysis(status: "bad").valid?
    a = analysis(elements: { iron: "-1", copper: "lots" })
    refute a.valid?
    assert_match "Iron and Copper", a.errors[:elements].first
    refute analysis(oil_properties: { fuel_percent: "x" }).valid?
    other_engine = create_component(create_aircraft)
    a = analysis(component: other_engine)
    refute a.valid?
    assert_includes a.errors[:component], "must be on this aircraft"
  end

  test "elements_in lists elements any sample has, in display order" do
    a = analysis(elements: { lead: 900, iron: 30 })
    b = analysis(elements: { zinc: 4 })
    assert_equal %w[iron lead zinc], OilAnalysis.elements_in([ a, b ])
  end
end

require "test_helper"

class OilAnalysisFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @aircraft = create_aircraft(owner: @owner, pilot: @pilot)
    @engine = create_component(@aircraft, hours_since_overhaul: 120.5)
  end

  def results(elements: {}, **overrides)
    { sample_date: "2026-08-01", status: "normal", component_id: @engine.id, lab: "Example Lab",
      engine_hours: 120.5, oil_hours: 40,
      elements: { iron: 30, copper: 6, lead: 2500, silicon: 22 }.merge(elements),
      element_averages: { iron: 35, copper: 9, lead: 2400, silicon: 12 } }.merge(overrides)
  end

  test "pilot adds samples; trends, flags and comparison render" do
    sign_in @pilot
    get new_aircraft_oil_analysis_path(@aircraft)
    assert_response :success
    assert_includes response.body, 'value="120.5"' # engine hours default from the engine

    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(sample_date: "2026-03-01", elements: { iron: 25, silicon: 10 }) }
    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(report: fixture_file_upload("engine_data/cgr30p.csv", "application/pdf")) }
    latest = @aircraft.oil_analyses.recent_first.first
    assert_redirected_to aircraft_oil_analysis_path(@aircraft, latest)
    assert latest.report.attached?
    assert_equal [ "Oil analysis added (sampled Aug 1, 2026)" ], @aircraft.events.where(category: "oil_analysis").limit(1).pluck(:event_name)

    get aircraft_oil_analyses_path(@aircraft)
    assert_response :success
    assert_includes response.body, "Silicon above average"
    assert_includes response.body, "Chartkick"

    get aircraft_oil_analysis_path(@aircraft, latest)
    assert_response :success
    assert_includes response.body, "Compared with"
    assert_includes response.body, "+5" # iron 25 → 30
    refute_includes response.body, ">Edit<" # pilots can't edit
  end

  test "only owners edit and delete" do
    analysis = @aircraft.oil_analyses.create!(results.except(:component_id))
    sign_in @pilot
    patch aircraft_oil_analysis_path(@aircraft, analysis), params: { oil_analysis: { status: "action_required" } }
    assert_equal "normal", analysis.reload.status

    sign_in @owner
    get edit_aircraft_oil_analysis_path(@aircraft, analysis)
    assert_response :success
    assert_select "input[name='oil_analysis[elements][iron]'][value='30.0']"
    assert_select "input[name='oil_analysis[elements][zinc]']" # the extra elements are there too
    patch aircraft_oil_analysis_path(@aircraft, analysis), params: { oil_analysis: { status: "monitor", elements: { iron: "", copper: "6", lead: "2500", silicon: "22", zinc: "4" } } }
    analysis.reload
    assert_equal "monitor", analysis.status
    assert_nil analysis.value("iron")
    assert_equal 4.0, analysis.value("zinc")
    delete aircraft_oil_analysis_path(@aircraft, analysis)
    assert_equal 0, @aircraft.oil_analyses.count
  end

  test "oil type, properties and leaving a sample out of trends" do
    sign_in @owner
    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(sample_date: "2026-03-01", elements: { iron: 25 }) }
    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(sample_date: "2026-05-01", elements: { iron: 90 }, excluded_from_averages: "1") }
    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(oil_type: "Aeroshell W100 Plus", status: "",
                                                                                oil_properties: { flashpoint_f: "445", fuel_percent: "0.5" }) }
    latest = @aircraft.oil_analyses.recent_first.first
    assert_nil latest.status

    get aircraft_oil_analysis_path(@aircraft, latest)
    assert_includes response.body, "Aeroshell W100 Plus"
    assert_includes response.body, "445 °F"
    assert_includes response.body, "Not rated"

    get aircraft_oil_analyses_path(@aircraft)
    assert_includes response.body, "left out of trends"
    iron = response.body[/"name":"Iron","data":\[(.*?)\]\]/, 1]
    assert_includes iron, "25.0"
    refute_includes iron, "90.0" # the excluded sample isn't charted
  end

  test "an engine from another aircraft is ignored" do
    other = create_component(create_aircraft)
    sign_in @owner
    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(component_id: other.id) }
    assert_nil @aircraft.oil_analyses.last.component_id
  end
end

class OilAnalysisImportTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @aircraft = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345")
    @in_service = create_component(@aircraft)
    @engine = create_component(@aircraft, serial_number: "900001", status: "SPARE")
  end

  def report = fixture_file_upload("oil_analysis/avlab_report.pdf", "application/pdf")

  test "pilot imports every sample on the report; reimporting adds nothing" do
    sign_in @pilot
    post import_aircraft_oil_analyses_path(@aircraft), params: { report: report }
    assert_redirected_to aircraft_oil_analyses_path(@aircraft)
    assert_equal "Imported 3 samples from the AvLab report.", flash[:notice]

    analyses = @aircraft.oil_analyses.recent_first.to_a
    assert_equal %w[P26 P47 P69], analyses.map(&:sample_number)
    assert analyses.all? { _1.component == @engine && _1.lab == "AvLab" } # matched by engine serial
    assert analyses.first.report.attached?
    refute analyses.last.report.attached?
    assert_equal 44.0, analyses.first.value("iron")
    assert_equal 13.7, analyses.first.average("silicon")
    assert_equal 3, @aircraft.events.where(category: "oil_analysis").count

    post import_aircraft_oil_analyses_path(@aircraft), params: { report: report }
    assert_equal "Imported 0 samples from the AvLab report. 3 samples were already recorded.", flash[:notice]
    assert_equal 3, @aircraft.oil_analyses.count

    follow_redirect!
    assert_includes response.body, "Silicon above average"
  end

  test "attaches the PDF to a matching sample entered by hand" do
    manual = @aircraft.oil_analyses.create!(sample_date: Date.new(2026, 8, 20), elements: { iron: 44 })
    sign_in @owner
    post import_aircraft_oil_analyses_path(@aircraft), params: { report: report }
    assert_equal 3, @aircraft.oil_analyses.count
    assert manual.reload.report.attached?
  end

  test "refuses a report for another aircraft, or a file that isn't one" do
    @aircraft.update!(tail_number: "N54321")
    sign_in @owner
    post import_aircraft_oil_analyses_path(@aircraft), params: { report: report }
    assert_redirected_to new_aircraft_oil_analysis_path(@aircraft)
    assert_equal "That report is for N12345, not N54321.", flash[:alert]

    post import_aircraft_oil_analyses_path(@aircraft), params: { report: fixture_file_upload("flights.csv", "application/pdf") }
    assert_match(/Couldn't import that report/, flash[:alert])
    assert_equal 0, @aircraft.oil_analyses.count
  end

  test "imports a Blackstone report: 20 elements, properties, oil type, unrated" do
    sign_in @owner
    post import_aircraft_oil_analyses_path(@aircraft), params: { report: fixture_file_upload("oil_analysis/blackstone_report.pdf", "application/pdf") }
    assert_equal "Imported 5 samples from the Blackstone report.", flash[:notice]
    latest = @aircraft.oil_analyses.recent_first.first
    assert_equal [ Date.new(2024, 1, 25), "Blackstone", "Phillips XC (A/C) 20W/50", nil, @in_service ],
                 [ latest.sample_date, latest.lab, latest.oil_type, latest.status, latest.component ] # no engine S/N: the engine in service
    assert_equal 20, latest.elements.size
    assert_equal 445.0, latest.property("flashpoint_f")
    assert latest.report.attached?

    follow_redirect!
    assert_select "td", text: "Zinc"
    assert_includes response.body, "Viscosity @ 100°C"
    assert_match(/Iron, Copper, .* above average/, response.body) # 2019: iron 818 ppm vs the 35 ppm universal average
  end
end

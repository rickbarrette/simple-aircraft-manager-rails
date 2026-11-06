require "test_helper"

class OilAnalysisFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @aircraft = create_aircraft(owner: @owner, pilot: @pilot)
    @engine = create_component(@aircraft, hours_since_overhaul: 120.5)
  end

  def results(**overrides)
    { sample_date: "2026-08-01", status: "normal", component_id: @engine.id, lab: "Example Lab",
      engine_hours: 120.5, oil_hours: 40, iron: 30, iron_avg: 35, copper: 6, copper_avg: 9,
      lead: 2500, lead_avg: 2400, silicon: 22, silicon_avg: 12 }.merge(overrides)
  end

  test "pilot adds samples; trends, flags and comparison render" do
    sign_in @pilot
    get new_aircraft_oil_analysis_path(@aircraft)
    assert_response :success
    assert_includes response.body, 'value="120.5"' # engine hours default from the engine

    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(sample_date: "2026-03-01", iron: 25, silicon: 10) }
    post aircraft_oil_analyses_path(@aircraft), params: { oil_analysis: results(report: fixture_file_upload("engine_data/cgr30p.csv", "application/pdf")) }
    latest = @aircraft.oil_analyses.recent_first.first
    assert_redirected_to aircraft_oil_analysis_path(@aircraft, latest)
    assert latest.report.attached?
    assert_equal [ "Oil analysis added (sampled 2026-08-01)" ], @aircraft.events.where(category: "oil_analysis").limit(1).pluck(:event_name)

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
    patch aircraft_oil_analysis_path(@aircraft, analysis), params: { oil_analysis: { status: "high" } }
    assert_equal "normal", analysis.reload.status

    sign_in @owner
    get edit_aircraft_oil_analysis_path(@aircraft, analysis)
    assert_response :success
    patch aircraft_oil_analysis_path(@aircraft, analysis), params: { oil_analysis: { status: "elevated", iron: "" } }
    assert_equal "elevated", analysis.reload.status
    assert_nil analysis.iron
    delete aircraft_oil_analysis_path(@aircraft, analysis)
    assert_equal 0, @aircraft.oil_analyses.count
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
    assert_equal 44.0, analyses.first.iron.to_f
    assert_equal 13.7, analyses.first.silicon_avg.to_f
    assert_equal 3, @aircraft.events.where(category: "oil_analysis").count

    post import_aircraft_oil_analyses_path(@aircraft), params: { report: report }
    assert_equal "Imported 0 samples from the AvLab report. 3 samples were already recorded.", flash[:notice]
    assert_equal 3, @aircraft.oil_analyses.count

    follow_redirect!
    assert_includes response.body, "Silicon above average"
  end

  test "attaches the PDF to a matching sample entered by hand" do
    manual = @aircraft.oil_analyses.create!(sample_date: Date.new(2026, 8, 20), iron: 44)
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
end

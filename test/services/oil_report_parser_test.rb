require "test_helper"

class OilReportParserTest < ActiveSupport::TestCase
  # A real AvLab report rebuilt with glyph positions intact (including the hidden
  # color-code layer that overlaps the results) and a dummy header.
  def report = @report ||= OilReportParser.from_pdf(file_fixture("oil_analysis/avlab_report.pdf").open)

  test "reads the header" do
    assert_equal "AvLab", report.lab
    assert_equal "N12345", report.tail_number
    assert_equal "900001", report.engine_serial
    assert_equal "CONT. 200", report.engine_model
  end

  test "reads the current sample and both previous ones" do
    assert_equal [ true, false, false ], report.samples.map { _1[:current] }
    current = report.samples.first
    assert_equal Date.new(2026, 8, 20), current[:sample_date]
    assert_equal Date.new(2026, 9, 3), current[:analysis_date]
    assert_equal "P26", current[:sample_number]
    assert_equal [ 94.7, 43.7, 43.7, 1 ], current.values_at(:engine_hours, :oil_hours, :filter_hours, :oil_added).map(&:to_f)
    assert_equal "normal", current[:status]
    assert_match(/ALL OIL VALUES SEEM FINE/, current[:lab_comments])
  end

  test "reads results and lab averages through the color-code layer" do
    current, previous1, previous2 = report.samples
    assert_equal({ iron: 44.0, copper: 8.1, nickel: 2.5, chromium: 3.9, aluminum: 6.7, lead: 2650.0, silicon: 25.3, tin: 1.6 },
                 current.slice(:iron, :copper, :nickel, :chromium, :aluminum, :lead, :silicon, :tin).transform_values(&:to_f))
    assert_equal({ iron_avg: 40.5, lead_avg: 2654.0, tin_avg: 3.2 }, current.slice(:iron_avg, :lead_avg, :tin_avg).transform_values(&:to_f))
    assert_nil current[:silver]      # N/A
    assert_nil current[:silver_avg]
    assert_equal 0.3, previous1[:nickel].to_f # a real "0" hidden under a color-code "0"
    assert_equal 0, previous1[:tin]           # "< 0.1"
    assert_equal 2024.0, previous2[:lead].to_f
    assert_equal 58.7, previous2[:iron].to_f  # not overwritten by "Cylinder Type: steel"
  end

  test "rejects other PDFs and non-PDFs" do
    assert_raises(OilReportParser::Error) { OilReportParser.from_pdf(StringIO.new("not a pdf")) }
    assert_raises(OilReportParser::Error) { OilReportParser.new([]).parse }
  end
end

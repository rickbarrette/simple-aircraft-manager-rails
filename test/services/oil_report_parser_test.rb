require "test_helper"

class OilReportParserTest < ActiveSupport::TestCase
  def parse(name) = OilReportParser.from_pdf(file_fixture("oil_analysis/#{name}").open)

  # A real AvLab report rebuilt with glyph positions intact (including the hidden
  # color-code layer that overlaps the results) and a dummy header.
  def avlab = @avlab ||= parse("avlab_report.pdf")

  # Anonymized sample reports from the original Simple Aircraft Manager project's
  # test suite (public domain): an older AvLab layout and a Blackstone report.
  def older_avlab = @older_avlab ||= parse("avlab_older_report.pdf")
  def blackstone = @blackstone ||= parse("blackstone_report.pdf")

  test "AvLab: reads the header" do
    assert_equal "AvLab", avlab.lab
    assert_equal "N12345", avlab.tail_number
    assert_equal "900001", avlab.engine_serial
    assert_equal "CONT. 200", avlab.engine_model
  end

  test "AvLab: reads the current sample and both previous ones" do
    assert_equal [ true, false, false ], avlab.samples.map { _1[:current] }
    current = avlab.samples.first
    assert_equal Date.new(2026, 8, 20), current[:sample_date]
    assert_equal Date.new(2026, 9, 3), current[:analysis_date]
    assert_equal "P26", current[:sample_number]
    assert_equal [ 94.7, 43.7, 43.7, 1 ], current.values_at(:engine_hours, :oil_hours, :filter_hours, :oil_added).map(&:to_f)
    assert_equal "normal", current[:status]
    assert_equal "ALL OIL VALUES SEEM FINE. WE WILL CONTINUE TO MONITOR THIS ENGINE WITH YOUR NEXT SAMPLE.", current[:lab_comments]
  end

  test "AvLab: reads results and lab averages through the color-code layer" do
    current, previous1, previous2 = avlab.samples.map { |s| [ s[:elements].transform_values(&:to_f), s[:element_averages].transform_values(&:to_f) ] }
    assert_equal({ "iron" => 44.0, "copper" => 8.1, "nickel" => 2.5, "chromium" => 3.9, "aluminum" => 6.7, "lead" => 2650.0, "silicon" => 25.3, "tin" => 1.6 },
                 current[0].slice("iron", "copper", "nickel", "chromium", "aluminum", "lead", "silicon", "tin"))
    assert_equal({ "iron" => 40.5, "lead" => 2654.0, "tin" => 3.2 }, current[1].slice("iron", "lead", "tin"))
    refute current[0].key?("silver") # N/A
    refute current[1].key?("silver")
    assert_equal 0.3, previous1[0]["nickel"] # a real "0" hidden under a color-code "0"
    assert_equal 0, previous1[0]["tin"]      # "< 0.1"
    assert_equal 2024.0, previous2[0]["lead"]
    assert_equal 58.7, previous2[0]["iron"]  # not overwritten by "Cylinder Type: steel"
  end

  test "AvLab, older layout: unused labels don't steal values; comments span lines" do
    current, previous = older_avlab.samples
    assert_nil current[:oil_added] # the "Filter Wt. (mgs): 121" beside it isn't oil added
    assert_equal "normal", current[:status]
    assert_match(/\AALL METALLIC DEBRIS .* WITH YOUR NEXT SAMPLE\.\z/, current[:lab_comments])
    assert_equal "monitor", previous[:status] # "** SEE LAB COMMENTS **"
    assert_match "CLOSEST MATCH AMS# 6274, WITH THE LARGEST PIECE", previous[:lab_comments]
    assert_equal [ 518.1, 43, 5 ], previous.values_at(:engine_hours, :oil_hours, :oil_added).map(&:to_f)
    assert_equal({ "aluminum" => 6.8, "chromium" => 4.1, "copper" => 13.0, "iron" => 30.2, "lead" => 1510.0, "nickel" => 0.5, "silicon" => 3.7, "tin" => 0.0 },
                 previous[:elements].transform_values(&:to_f).sort.to_h)
  end

  test "Blackstone: header, five samples newest first, no rating" do
    assert_equal "Blackstone", blackstone.lab
    assert_equal "Phillips XC (A/C) 20W/50", blackstone.oil_type
    assert_equal "Generic Engine", blackstone.engine_model
    assert_nil blackstone.tail_number # "N0000X" isn't a real registration
    assert_equal %w[2024-01-25 2022-03-31 2021-08-12 2020-06-08 2019-12-30], blackstone.samples.map { _1[:sample_date].iso8601 }
    assert_equal [ true, false, false, false, false ], blackstone.samples.map { _1[:current] }
    assert blackstone.samples.all? { _1[:status].nil? }
    current = blackstone.samples.first
    assert_equal "S000000", current[:sample_number]
    assert_match(/\ALorem ipsum dolor sit amet.* id est laborum\.\z/, current[:lab_comments])
    assert_nil blackstone.samples.second[:lab_comments]
  end

  test "Blackstone: hours, all 20 elements, universal averages and oil properties per column" do
    current, second, _, fourth, oldest = blackstone.samples
    assert_equal [ 43, 518, 5 ], current.values_at(:oil_hours, :engine_hours, :oil_added).map(&:to_f)
    assert_equal 1903, fourth[:engine_hours].to_i # "1,903"
    assert_nil blackstone.samples.third[:oil_added]
    assert_equal 20, current[:elements].size
    assert_equal({ "iron" => 36.0, "lead" => 1841.0, "aluminum" => 7.0, "zinc" => 4.0, "barium" => 0.0 },
                 current[:elements].slice("iron", "lead", "aluminum", "zinc", "barium").transform_values(&:to_f))
    assert_equal 807.0, second[:elements]["lead"].to_f # skips the unit/location average column (1458)
    assert_equal 818.0, oldest[:elements]["iron"].to_f
    assert_equal({ "iron" => 35.0, "lead" => 2354.0, "phosphorus" => 415.0 },
                 current[:element_averages].slice("iron", "lead", "phosphorus").transform_values(&:to_f))
    assert_equal({ "viscosity_sus_210f" => 95.3, "viscosity_cst_100c" => 19.24, "flashpoint_f" => 445.0, "fuel_percent" => 0.5, "water_percent" => 0.0, "insolubles_percent" => 0.3 },
                 current[:oil_properties].transform_values(&:to_f))
    assert_equal 490.0, oldest[:oil_properties]["flashpoint_f"].to_f
  end

  test "rejects other PDFs and non-PDFs" do
    assert_raises(OilReportParser::Error) { OilReportParser.from_pdf(StringIO.new("not a pdf")) }
    assert_raises(OilReportParser::Error) { OilReportParser::Avlab.new([]).parse }
    error = assert_raises(OilReportParser::Error) { parse_pdf_text("Just some other document") }
    assert_match "AvLab and Blackstone", error.message
  end

  private

  # A minimal one-page PDF with the given text.
  def parse_pdf_text(text)
    objects = [ "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
                nil, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>" ]
    stream = "BT /F1 12 Tf 72 720 Td (#{text}) Tj ET"
    objects[3] = "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
    pdf = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map { |body, i| pdf.bytesize.tap { pdf << "#{i + 1} 0 obj\n#{body}\nendobj\n" } }
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n" << offsets.map { format("%010d 00000 n \n", _1) }.join
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    OilReportParser.from_pdf(StringIO.new(pdf))
  end
end

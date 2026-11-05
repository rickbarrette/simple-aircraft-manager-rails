require "test_helper"

class AdImportTest < ActiveSupport::TestCase
  FILE = Rails.root.join("test/fixtures/files/drs_ads.csv")

  setup do
    @user = create_user
    @aircraft = create_aircraft(owner: @user, make: "Cessna", model: "150L", tach_time: 7290.3)
  end

  def import = AdImport.new(@aircraft, path: FILE, filename: "AD Final Rules.csv")
  def row(number) = import.rows.find { _1.number == number }

  test "parses the DRS export and cleans the Federal Register text" do
    rows = import.rows
    assert_equal [ "2011-10-09", "2008-22-18", "96-12-22", "75-15-08", "87-20-03 R2" ], rows.map(&:number)
    seat = rows.first
    assert_equal "Seat Rails and Roller Housing Inspections", seat.subject
    assert_equal Date.new(2011, 6, 17), seat.effective_date
    assert_equal "FAA-2010-1101", seat.docket
    assert_equal [ "87-20-03 R2" ], seat.supersedes
    assert_not_includes seat.summary, "((Page"
    assert_not_includes seat.summary, "\\n"
    assert_nil rows[3].docket # "Unknown"
  end

  test "suggests an action and flags things to check" do
    assert_equal "track", row("2011-10-09").suggested
    assert_match "repetitive", row("2011-10-09").notes.join

    assert_match "STC", row("2008-22-18").notes.join
    assert_match "Appliance", row("96-12-22").notes.join

    old = row("87-20-03 R2")
    assert_equal "skip", old.suggested
    assert_match "Historical", old.notes.join
    assert_match "Superseded by 2011-10-09", old.notes.join
  end

  test "skips ADs whose model list doesn't include the aircraft" do
    @aircraft.update!(model: "150M")
    assert_equal "skip", row("75-15-08").suggested
    assert_match "150M", row("75-15-08").notes.join
  end

  test "model written with the make still matches" do
    @aircraft.update!(model: "Cessna 150L")
    assert_equal "track", row("75-15-08").suggested
  end

  test "imports with per-AD decisions; tracked ADs need compliance, N/A ones don't" do
    result = import.import!(decisions: { "2008-22-18" => "na", "96-12-22" => "skip" }, user: @user)
    assert_equal({ tracked: 2, not_applicable: 1, skipped: 2, updated: 0 }, result)
    assert_equal %w[2008-22-18 2011-10-09 75-15-08], @aircraft.applicable_ads.order(:name).pluck(:name)

    rows = Compliance.ad_rows(@aircraft).index_by { _1.ad.name }
    assert_equal "not_applicable", rows["2008-22-18"].status
    assert_equal "no_compliance", rows["2011-10-09"].status

    issues = Airworthiness.new(@aircraft).call.issues.map(&:title)
    assert_includes issues, "AD 2011-10-09 - Overdue"
    assert_not issues.any? { _1.include?("2008-22-18") }

    ad = AirworthinessDirective.find_by(name: "2011-10-09")
    assert_equal "87-20-03 R2", ad.supersedes
    assert_includes ad.applicable_models, "150L"
  end

  test "re-import updates existing ADs from the FAA data and says what changes" do
    mine = AirworthinessDirective.create!(name: "2011-10-09", short_description: "My seat rail notes", recurring: true, recurring_hours: 100)
    mine.aircraft << @aircraft
    mine.ad_compliances.create!(aircraft: @aircraft, date_complied: Date.current, compliance_notes: "Done", next_due_at_time: 7390.3)
    r = row("2011-10-09")
    assert_equal "track", r.suggested
    assert_match "Already tracked. Will update: Subject, Summary, Effective date, Docket, Supersedes, Models, Product type", r.notes.first

    result = import.import!(decisions: {}, user: @user)
    assert_equal 1, result[:updated]
    assert_equal 1, AirworthinessDirective.where(name: "2011-10-09").count
    mine.reload
    assert_equal "Seat Rails and Roller Housing Inspections", mine.short_description
    assert_equal Date.new(2011, 6, 17), mine.effective_date
    # owner-managed settings and compliance untouched
    assert mine.recurring?
    assert_equal 100, mine.recurring_hours
    assert_equal BigDecimal("7390.3"), mine.ad_compliances.first.next_due_at_time

    assert_match "Up to date", row("2011-10-09").notes.first
  end

  test "a tracked AD that's now superseded is updated and flagged, not skipped" do
    old = AirworthinessDirective.create!(name: "87-20-03 R2", short_description: "Old seat rail AD")
    old.aircraft << @aircraft
    r = row("87-20-03 R2")
    assert_equal "track", r.suggested
    assert_match "Superseded by 2011-10-09: review whether it still applies", r.notes.join

    import.import!(decisions: { "87-20-03 R2" => "track" }, user: @user)
    assert_equal "2011-10-09", old.reload.superseded_by
  end

  test "skip leaves an existing AD exactly as it is" do
    mine = AirworthinessDirective.create!(name: "2011-10-09", short_description: "Mine")
    mine.aircraft << @aircraft
    import.import!(decisions: { "2011-10-09" => "skip" }, user: @user)
    assert_equal "Mine", mine.reload.short_description
    assert_nil mine.effective_date
  end

  test "a later Excel import adds DRS links to ADs imported from CSV" do
    import.import!(decisions: {}, user: @user)
    assert_nil AirworthinessDirective.find_by(name: "2011-10-09").document_url
    path = Rails.root.join("tmp/drs-#{SecureRandom.hex(4)}.xlsx")
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "ADs") do |ws|
      ws.add_row [ "AD Number", "Subject", "Status", "Model" ]
      ws.add_row [ "2011-10-09", "Seat Rails and Roller Housing Inspections", "Current", "150L" ]
      ws.add_hyperlink(location: "https://drs.faa.gov/browse/excelExternalWindow/XYZ.0001", ref: "A2")
    end
    pkg.serialize(path.to_s)
    xlsx = AdImport.new(@aircraft, path: path, filename: "ads.xlsx")
    assert_match "DRS link", xlsx.rows.first.notes.first
    xlsx.import!(decisions: {}, user: @user)
    ad = AirworthinessDirective.find_by(name: "2011-10-09")
    assert_equal "https://drs.faa.gov/browse/excelExternalWindow/XYZ.0001", ad.document_url
    assert_equal Date.new(2011, 6, 17), ad.effective_date # not blanked by the sparser file
  ensure
    FileUtils.rm_f(path) if path
  end

  test "warns when a new AD supersedes one the aircraft still tracks" do
    AirworthinessDirective.create!(name: "87-20-03 R2", short_description: "Old seat rail AD").aircraft << @aircraft
    assert_match "Supersedes 87-20-03 R2", row("2011-10-09").notes.join
  end

  test "re-import is idempotent and N/A isn't recorded twice" do
    2.times { import.import!(decisions: { "2008-22-18" => "na" }, user: @user) }
    assert_equal 1, AdCompliance.where(not_applicable: true).count
    assert_equal 4, @aircraft.applicable_ads.count
  end

  test "keeps hyperlinks from an Excel export" do
    path = Rails.root.join("tmp/drs-#{SecureRandom.hex(4)}.xlsx")
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "ADs") do |ws|
      ws.add_row [ "AD Number", "Subject", "Status", "Effective Date", "Model" ]
      ws.add_row [ "2011-10-09", "Seat Rails", "Current", "06/17/2011", "150L" ]
      ws.add_row [ "67-03-01", "Exhaust Gas Heat Exchangers", "Current", "01/14/1967", "150L" ]
      ws.add_hyperlink(location: "https://drs.faa.gov/browse/excelExternalWindow/ABC123.0001", ref: "A2")
    end
    pkg.serialize(path.to_s)

    imp = AdImport.new(@aircraft, path: path, filename: "ads.xlsx")
    assert_equal "https://drs.faa.gov/browse/excelExternalWindow/ABC123.0001", imp.rows.first.url
    assert_nil imp.rows.last.url
    imp.import!(decisions: {}, user: @user)
    assert_equal [ "https://drs.faa.gov/browse/excelExternalWindow/ABC123.0001", "View AD" ],
                 AirworthinessDirective.find_by(name: "2011-10-09").reference_link
  ensure
    FileUtils.rm_f(path)
  end

  test "keeps a link column from a CSV, but never non-http links" do
    path = Rails.root.join("tmp/drs-#{SecureRandom.hex(4)}.csv")
    File.write(path, <<~CSV)
      AD Number,Subject,Status,Model,Link
      2011-10-09,Seat Rails,Current,150L,https://example.gov/ad/2011-10-09.pdf
      2008-22-18,BRS,Current,150L,javascript:alert(1)
    CSV
    rows = AdImport.new(@aircraft, path: path, filename: "x.csv").rows
    assert_equal "https://example.gov/ad/2011-10-09.pdf", rows.first.url
    assert_nil rows.last.url
  ensure
    FileUtils.rm_f(path)
  end

  # Guards against a field only existing in memory (e.g. via `normalizes`)
  # and silently not being saved.
  test "every FAA field the import writes is a real database column" do
    AdImport::FAA_FIELDS.each_key do |attr|
      assert_includes AirworthinessDirective.column_names, attr.to_s
    end
    assert_includes Aircraft.column_names, "drs_search_url"
  end

  test "rejects files that aren't DRS exports" do
    path = Rails.root.join("tmp/not-drs-#{SecureRandom.hex(4)}.csv")
    File.write(path, "Name,Value\na,1\n")
    assert_raises(AdImport::Error) { AdImport.new(@aircraft, path: path, filename: "x.csv").rows }
  ensure
    FileUtils.rm_f(path)
  end
end

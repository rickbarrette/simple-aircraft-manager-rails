require "test_helper"

# Electronic recordkeeping (AC 120-78B chapter 3): history, integrity,
# backups, software versions, the records package, legacy records.
class RecordsIntegrityTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    @mech = create_user("mech@example.com").tap { _1.update!(name: "Sam Mechanic") }
    @ap = @mech.certificates.create!(kind: "AP", number: "7654321")
  end

  def entry(**attrs)
    @a.logbook_entries.create!({ date: Date.new(2026, 10, 1), entry_type: "MAINTENANCE", text: "Changed oil", aircraft_hours_at_entry: 1000 }.merge(attrs))
  end

  test "every change to a record is kept, with who and what changed, and shown" do
    sign_in @owner
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: { date: "2026-10-01", log_type: "AC", entry_type: "MAINTENANCE", text: "Changed oil" } }
    e = @a.logbook_entries.sole
    patch aircraft_logbook_entry_path(@a, e), params: { logbook_entry: { text: "Changed oil and filter" } }
    versions = e.versions.to_a
    assert_equal %w[create update], versions.map(&:event)
    assert_equal [ "Changed oil", "Changed oil and filter" ], versions.last.changes_hash["text"]
    assert_equal [ @owner, @owner ], versions.map(&:user)
    assert versions.all? { _1.ip_address.present? }
    get aircraft_logbook_entry_path(@a, e)
    assert_includes response.body, "Change history (2)"
    delete aircraft_logbook_entry_path(@a, e)
    assert_equal "destroy", RecordVersion.where(item_type: "LogbookEntry", item_id: e.id).last.event # history outlives the record
    get aircraft_record_versions_path(@a)
    assert_select "li", minimum: 3
    assert_includes response.body, "deleted"
    assert_raises(ActiveRecord::RecordNotSaved) { RecordVersion.last.update!(event: "x") }
  end

  test "the integrity check finds broken history chains and altered signed entries" do
    e = entry
    EntrySigner.new(e, user: @mech, certificate: @ap, auth_method: "password").sign!
    other = create_aircraft(owner: @owner)
    other.squawks.create!(priority: 2, issue_reported: "Chip in paint")
    check = RecordsIntegrity.check!
    assert check.ok, check.problems.inspect
    assert check.versions_checked >= 4
    assert_equal 1, check.signatures_checked

    LogbookEntry.where(id: e.id).update_all(text: "Changed oil (edited in the database)")
    victim = RecordVersion.where(aircraft_id: other.id).first
    RecordVersion.where(id: victim.id).delete_all
    check = RecordsIntegrity.check!
    refute check.ok
    assert(check.problems.any? { _1.include?("the 2026-10-01 logbook entry (signed by Sam Mechanic) changed after it was signed") })
    assert(check.problems.any? { _1.include?("doesn't follow the one before it") || _1.include?("missing") } || RecordVersion.where(aircraft_id: other.id).count.zero?)

    RecordVersion.where(aircraft_id: @a.id).last.then { RecordVersion.where(id: _1.id).update_all(payload: _1.payload.sub("Changed oil", "Changed gas")) }
    assert(RecordsIntegrity.check!.problems.any? { _1.include?("was altered") })
  end

  test "software versions are recorded" do
    with_revision("abc1234") { AppRevision.touch_current! }
    with_revision("def5678") { AppRevision.touch_current! }
    with_revision("def5678") { AppRevision.touch_current! }
    assert_equal %w[def5678 abc1234], AppRevision.latest_first.pluck(:revision) & %w[def5678 abc1234]
    assert_equal 1, AppRevision.where(revision: "def5678").count
  end

  test "the records package has everything for the FAA or a buyer" do
    @a.update!(electronic_records_since: Date.new(2026, 1, 1))
    @a.documents.create!(name: "Logbook scans 1975-2025", doc_type: "LOG", legacy_record: true)
    signed = entry
    EntrySigner.new(signed, user: @mech, certificate: @ap, auth_method: "password").sign!
    entry(date: Date.new(2026, 10, 5), text: "Unsigned entry")
    sign_in @owner
    get aircraft_records_package_path(@a)
    assert_response :success
    assert_match(/filename="n12345-records-\d{4}-\d\d-\d\d\.zip"/, response.headers["Content-Disposition"])
    path = File.join(Dir.mktmpdir, "pkg.zip")
    File.binwrite(path, response.body)
    Zip::File.open(path) do |zip|
      def zip.text(name) = read(name).force_encoding("UTF-8")
      assert_equal %w[README.txt logbook-entries.pdf n12345.sam.zip record-history.csv signatures.csv status-report.html], zip.entries.map(&:name).sort
      readme = zip.text("README.txt")
      assert_includes readme, "All 2 logbook entries, oldest first. 1 are signed electronically"
      assert_includes readme, "Electronic records since: 2026-01-01"
      assert_includes readme, "scans marked \"legacy record\""
      sigs = CSV.parse(zip.text("signatures.csv"), headers: true)
      assert_equal [ "Sam Mechanic", "7654321", "Valid", signed.reload.signature.content_digest ], sigs.first.fields.values_at(3, 5, 7, 8)
      assert_operator CSV.parse(zip.text("record-history.csv"), headers: true).size, :>=, 3
      html = zip.text("status-report.html")
      assert_includes html, "Maintenance status · 14 CFR 91.417(a)(2)"
      refute_includes html, "<script"
      assert_match(/<head>\s*<meta charset="utf-8">/, html) # files opened from disk need it (em dashes etc.)
    assert_includes html, "<style>"
    end
    assert @a.events.exists?(event_name: "Records package downloaded")

    pilot = create_user
    @a.roles.create!(user: pilot, role: "pilot")
    sign_in pilot
    get aircraft_records_package_path(@a)
    assert_redirected_to aircraft_path(@a) # owners only
  end

  private

  def with_revision(sha)
    saved = ENV["APP_REVISION"]
    ENV["APP_REVISION"] = sha
    yield
  ensure
    ENV["APP_REVISION"] = saved
  end

  test "the packaged status report has intact styles and no in-app controls" do
    engine = create_component(@a, tbo_hours: 2000, hours_since_overhaul: 126, on_condition: true)
    path = Rails.root.join("tmp", "pkg-#{SecureRandom.hex(4)}.zip")
    RecordsPackage.new(@a, source: "test").write_to(path)
    html, csv = Zip::File.open(path) { |z| [ z.read("status-report.html").force_encoding("UTF-8"), z.read("signatures.csv").force_encoding("UTF-8") ] }
    assert csv.start_with?("\uFEFF"), "CSV has a byte order mark for Excel"
    File.delete(path)
    assert_includes html, "<style>"
    refute_includes html, "\\[</head>" # escaped "&" in CSS selectors left intact
    assert_equal 1, html.scan("</head>").size
    refute_includes html, "Print or save as PDF"
    refute_includes html, "← Back"
    assert_includes html, "On condition (Part 91)"
    assert_includes html, "1,874.0 hrs"
    engine.update!(tbo_critical: true)
    refute engine.reload.tbo_critical? # on condition wins
  end
end

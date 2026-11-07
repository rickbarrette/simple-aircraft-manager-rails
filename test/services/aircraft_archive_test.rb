require "test_helper"

class AircraftArchiveTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  PNG = "\x89PNG\r\n\x1A\n".b + "rest-of-image".b

  setup do
    @owner = create_user("owner@example.com")
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@dir) }

  def upload(name, body, type) = { io: StringIO.new(body), filename: name, content_type: type }

  # An aircraft with something in every section.
  def full_aircraft
    a = create_aircraft(owner: @owner, tail_number: "N12345", make: "Cessna", model: "150", icao_type: "C150", tach_time: 2000)
    a.picture.attach(upload("plane.png", PNG, "image/png"))
    engine = create_component(a, serial_number: "900001", component_type: component_type("Engine"))
    oil = create_component(a, parent_component: engine, component_type: component_type("Oil"), replacement_critical: true, replacement_hours: 50)
    collection = a.document_collections.create!(name: "Logbooks", visibility: "maintenance")
    doc = a.documents.create!(name: "Engine log", document_collection: collection, doc_type: "LOG")
    doc.pages.attach(upload("page1.pdf", "%PDF-1.4 page one", "application/pdf"), upload("page2.png", PNG, "image/png"))
    entry = a.logbook_entries.create!(date: Date.new(2026, 1, 5), text: "Oil changed", log_type: "ENG", document: doc, aircraft_hours_at_entry: 1990)
    a.squawks.create!(priority: 1, issue_reported: "Cracked fairing", component: engine, reported_by: @owner,
                      attachments: [ upload("crack.png", PNG, "image/png"), upload("notes.txt", "see photo", "text/plain") ])
    a.squawks.create!(priority: 3, issue_reported: "Old one", resolved: true, resolved_at: 1.day.ago)
    annual = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12)
    annual.aircraft << a
    record = a.inspection_records.create!(inspection_type: annual, date: Date.new(2026, 2, 1), aircraft_hours: 1995, logbook_entry: entry)
    ad = AirworthinessDirective.create!(name: "2020-01-01", short_description: "Check muffler", recurring: true, recurring_hours: 100, docket_number: "FAA-2020-1")
    ad.components << engine
    a.ad_compliances.create!(airworthiness_directive: ad, date_complied: Date.new(2026, 2, 1), next_due_at_time: 2095, compliance_notes: "Inspected",
                             component: engine, inspection_record: record)
    flight = a.flight_logs.create!(date: Date.new(2025, 7, 14), tach_time: 1.2, departure_location: "KOQU", destination_location: "KBID",
                                   user: @owner, track_log: { io: file_fixture("tracks/flight.gpx").open, filename: "flight.gpx" },
                                   engine_data: { io: file_fixture("engine_data/cgr30p.csv").open, filename: "cgr30p.csv" })
    a.consumable_records.create!(record_type: "oil", date: Date.new(2026, 1, 5), quantity_added: 1, flight_hours: 1990, flight_log: flight)
    a.major_records.create!(record_type: "alteration", title: "LED lights", date_performed: Date.new(2025, 5, 1), form_337_document: doc)
    a.notes.create!(text: "Hangar 4", public: true, user: @owner)
    a.oil_analyses.create!(sample_date: Date.new(2026, 1, 5), lab: "Blackstone", sample_number: "S1", component: engine, oil_type: "W100",
                           elements: { iron: 30, zinc: 4 }, element_averages: { iron: 35 }, oil_properties: { flashpoint_f: 445 },
                           excluded_from_averages: true, report: upload("report.pdf", "%PDF-1.4 lab", "application/pdf"))
    a
  end

  def export(aircraft)
    path = File.join(@dir, "export.sam.zip")
    AircraftArchive::Exporter.new(aircraft, source: "sam.example.com").write_to(path)
    path
  end

  def manifest(path) = Zip::File.open(path) { JSON.parse(_1.read("manifest.json")) }

  test "export writes a manifest the original app accepts, plus every file" do
    path = export(full_aircraft)
    data = manifest(path)
    assert_equal AircraftArchive::TOP_LEVEL_KEYS.sort, data.keys.sort # the original rejects unknown or missing top-level keys
    assert_equal 2, data["schema_version"]
    assert_equal "N12345", data["aircraft"]["tail_number"]
    assert_equal 2, data["document_images"].size
    squawk = data["squawks"].find { _1["issue_reported"] == "Cracked fairing" }
    assert_equal 2, squawk["attachments"].size
    assert_equal squawk["attachments"].first, squawk["attachment"] # what the original reads
    oil = data["oil_analysis_reports"].first
    assert_equal({ "iron" => 30.0, "zinc" => 4.0 }, oil["elements_ppm"])
    assert_equal "S1", oil["lab_number"]

    files = Zip::File.open(path) { |zip| zip.entries.map(&:name) - [ "manifest.json" ] }
    assert_equal 8, files.size # picture, 2 document pages, 2 squawk files, track log, engine data, oil report
    assert files.all? { _1.start_with?("attachments/") }
    assert files.any? { _1.end_with?("/crack.png") }, "original filenames are kept"
  end

  test "round trip: importing an export recreates the aircraft with new IDs" do
    original = full_aircraft
    path = export(original)
    other = create_user("other@example.com")
    result = AircraftArchive::Importer.new(path, owner: other, tail_number: "N54321").run
    a = result[:aircraft]

    assert_equal [ "N54321", "Cessna", "150", "C150", 2000 ], [ a.tail_number, a.make, a.model, a.icao_type, a.tach_time.to_i ]
    refute_equal original.id, a.id
    assert a.picture.attached?
    assert_equal [ "owner" ], a.roles.where(user: other).pluck(:role)
    assert_equal 2, a.components.count
    oil = a.components.find_by(component_type: component_type("Oil"))
    assert_equal a.components.find_by(serial_number: "900001"), oil.parent_component
    doc = a.documents.sole
    assert_equal %w[page1.pdf page2.png], doc.pages.map { _1.filename.to_s }
    assert_equal "%PDF-1.4 page one", doc.pages.first.download
    assert_equal doc, a.logbook_entries.sole.document
    squawk = a.squawks.find_by(issue_reported: "Cracked fairing")
    assert_equal %w[crack.png notes.txt], squawk.attachments.map { _1.filename.to_s }.sort
    assert_equal "IN-USE", squawk.component.status
    assert a.squawks.find_by(issue_reported: "Old one").resolved?
    assert_includes a.inspection_types.pluck(:name), "Annual"
    assert_equal 1, InspectionType.where(name: "Annual").count, "existing inspection types are reused"
    compliance = a.ad_compliances.sole
    assert_equal [ "2020-01-01", 2095 ], [ compliance.airworthiness_directive.name, compliance.next_due_at_time.to_i ]
    assert_equal a.inspection_records.sole, compliance.inspection_record
    assert_equal 1, AirworthinessDirective.where(name: "2020-01-01").count
    assert_includes compliance.airworthiness_directive.components, a.components.find_by(serial_number: "900001")
    flight = a.flight_logs.sole
    assert flight.track_log.attached?
    assert flight.engine_data.attached?
    assert_equal flight, a.consumable_records.sole.flight_log
    assert_equal doc, a.major_records.sole.form_337_document
    assert_match "Hangar 4", a.notes.sole.text
    analysis = a.oil_analyses.sole
    assert_equal [ "Blackstone", "S1", "W100", true ], [ analysis.lab, analysis.sample_number, analysis.oil_type, analysis.excluded_from_averages ]
    assert_equal({ "iron" => 30.0, "zinc" => 4.0 }, analysis.elements)
    assert_equal({ "iron" => 35.0 }, analysis.element_averages)
    assert analysis.report.attached?
    assert_equal "aircraft", a.events.last.category
    assert_empty result[:warnings]
  end

  test "imports an archive from the original app (UUIDs, its field names, links we don't keep)" do
    path = File.join(@dir, "original.sam.zip")
    ids = Hash.new { |h, k| h[k] = SecureRandom.uuid }
    data = AircraftArchive::TOP_LEVEL_KEYS.to_h { [ _1, [] ] }.merge(
      "schema_version" => 2, "exported_at" => "2026-10-01T12:00:00+00:00", "source_instance" => "sam.example.org",
      "aircraft" => { "id" => ids[:a], "tail_number" => "N0000X", "make" => "Piper", "model" => "PA-28", "status" => "AVAILABLE",
                      "tach_time" => "1234.5", "tach_time_offset" => "0.0", "hobbs_time" => "0.0", "hobbs_time_offset" => "0.0", "picture" => nil },
      "component_types" => [ { "id" => ids[:ct], "name" => "engine", "consumable" => false } ],
      "components" => [ { "id" => ids[:c], "aircraft_id" => ids[:a], "parent_component_id" => nil, "component_type_id" => ids[:ct],
                          "manufacturer" => "Lycoming", "model" => "O-360", "status" => "IN-USE", "date_in_service" => "2020-01-01",
                          "hours_in_service" => "500.0", "hours_since_overhaul" => "500.0", "tbo_hours" => 2000, "tbo_critical" => true } ],
      "logbook_entries" => [ { "id" => ids[:le], "aircraft_id" => ids[:a], "log_type" => "ENG", "date" => "2026-01-01", "text" => "Annual",
                               "components" => [ ids[:c] ], "component_hours" => { ids[:c] => 500.0 }, "entry_type" => "INSPECTION" } ],
      "squawks" => [ { "id" => ids[:s], "aircraft_id" => ids[:a], "priority" => 0, "issue_reported" => "Mag drop",
                       "attachment" => "attachments/health/squawks/abc123.png", "resolved" => false, "logbook_entries" => [] } ],
      "oil_analysis_reports" => [ { "id" => ids[:o], "aircraft_id" => ids[:a], "component_id" => ids[:c], "sample_date" => "2026-01-01",
                                    "lab" => "AVLab", "lab_number" => "", "oil_hours" => "40.0", "elements_ppm" => { "iron" => 12.5 },
                                    "oil_properties" => nil, "status" => "monitor", "excluded_from_averages" => false } ],
      "flight_logs" => [ { "id" => ids[:f], "aircraft_id" => ids[:a], "date" => "2026-02-01", "tach_time" => "1.3",
                           "track_log" => "attachments/track_logs/xyz.kml" } ],
      "features" => [ { "feature" => "airworthiness_enforcement", "enabled" => true }, { "feature" => "oil_analysis", "enabled" => true } ]
    )
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry("manifest.json")
      zip.write(data.to_json)
      zip.put_next_entry("attachments/health/squawks/abc123.png")
      zip.write(PNG)
      zip.put_next_entry("attachments/track_logs/xyz.kml")
      zip.write(file_fixture("tracks/flight.kml").read)
    end

    engine_type = component_type("Engine")
    preview = AircraftArchive::Importer.check(path)
    assert_equal [ "N0000X", "sam.example.org", 1 ], [ preview.tail_number, preview.source, preview.counts["components"] ]

    result = AircraftArchive::Importer.new(path, owner: @owner).run
    a = result[:aircraft]
    assert_equal [ "N0000X", "Piper", 1234.5 ], [ a.tail_number, a.make, a.tach_time.to_f ]
    assert_equal engine_type, a.components.sole.component_type, "matched case-insensitively"
    assert_equal 2000, a.components.sole.tbo_hours
    assert_equal "INSPECTION", a.logbook_entries.sole.entry_type
    squawk = a.squawks.sole
    assert_equal [ 0, "abc123.png" ], [ squawk.priority, squawk.attachments.sole.filename.to_s ]
    analysis = a.oil_analyses.sole
    assert_equal [ "monitor", 12.5, nil, a.components.sole ], [ analysis.status, analysis.value("iron"), analysis.sample_number, analysis.component ]
    assert a.flight_logs.sole.track_log.attached?
    assert_equal [ "1 logbook entry was linked to components; those links aren't kept here." ], result[:warnings]
  end

  test "a file whose contents don't match its name is skipped with a note" do
    path = export(full_aircraft)
    data = manifest(path)
    fake = data["squawks"].find { _1["attachments"].any? }["attachments"].first
    Zip::File.open(path) { |zip| zip.get_output_stream(fake) { _1.write("MZ not a png") } }
    result = AircraftArchive::Importer.new(path, owner: @owner, tail_number: "N777").run
    assert_equal 1, result[:aircraft].squawks.find_by(issue_reported: "Cracked fairing").attachments.count
    assert_match "doesn't contain what its name says (.png)", result[:warnings].sole
  end

  test "rejects unsafe or unrecognized archives before importing anything" do
    write = lambda do |entries|
      path = File.join(@dir, "#{SecureRandom.hex(4)}.zip")
      Zip::OutputStream.open(path) { |zip| entries.each { |name, body| zip.put_next_entry(name); zip.write(body) } }
      path
    end
    good = AircraftArchive::TOP_LEVEL_KEYS.to_h { [ _1, [] ] }.merge("schema_version" => 2, "aircraft" => { "tail_number" => "N1" })

    {
      write.({ "notes.txt" => "hi" }) => "no manifest.json",
      write.({ "manifest.json" => good.merge("schema_version" => 3).to_json }) => "Unsupported archive version 3",
      write.({ "manifest.json" => good.except("squawks").to_json }) => "missing squawks",
      write.({ "manifest.json" => good.to_json, "../../evil.txt" => "x" }) => "unsafe path",
      write.({ "manifest.json" => good.merge("aircraft" => {}).to_json }) => "no aircraft tail number",
      write.({ "manifest.json" => "{not json" }) => "couldn't be read",
      File.join(@dir, "missing.zip").tap { File.write(_1, "not a zip") } => "Not a valid .sam.zip"
    }.each do |path, message|
      error = assert_raises(AircraftArchive::Error) { AircraftArchive::Importer.check(path) }
      assert_match message, error.message
    end
    assert_equal 0, Aircraft.where(tail_number: "N1").count
  end

  test "a failure part-way removes everything the import created" do
    path = export(full_aircraft)
    before = [ Aircraft.count, Component.count, ActiveStorage::Blob.count ]
    importer = AircraftArchive::Importer.new(path, owner: @owner, tail_number: "N999")
    importer.define_singleton_method(:import_notes) { raise "disk on fire" }
    assert_raises(RuntimeError) { importer.run }
    assert_equal before[0, 2], [ Aircraft.count, Component.count ]
    assert_equal 0, Aircraft.where(tail_number: "N999").count
    perform_enqueued_jobs
    assert_equal before[2], ActiveStorage::Blob.count
  end
end

require "test_helper"

class AircraftArchiveFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345", make: "Cessna")
    engine = create_component(@a)
    @a.squawks.create!(priority: 1, issue_reported: "Cracked fairing", component: engine,
                       attachments: [ { io: StringIO.new("see photo"), filename: "notes.txt", content_type: "text/plain" } ])
    @a.logbook_entries.create!(date: Date.new(2026, 1, 5), text: "Oil changed")
  end

  def download_export
    get aircraft_export_path(@a)
    assert_response :success
    assert_equal "application/octet-stream", response.media_type # so Safari doesn't unzip it into a folder
    assert_match(/attachment; filename="n12345-[\d-]+\.sam\.zip"/, response.headers["Content-Disposition"])
    path = File.join(Dir.mktmpdir, "export.sam.zip")
    File.binwrite(path, response.body)
    path
  end

  test "owner downloads an export; pilots and outsiders can't" do
    sign_in @pilot
    get aircraft_export_path(@a)
    assert_redirected_to aircraft_path(@a)

    sign_in create_user
    get aircraft_export_path(@a)
    assert_response :not_found

    sign_in @owner
    get aircraft_aircraft_roles_path(@a)
    assert_select "a[href='#{aircraft_export_path(@a)}']", text: "Download .sam.zip"
    path = download_export
    assert_match(/attachment; filename="n12345-\d{4}-\d\d-\d\d\.sam\.zip"/, response.headers["Content-Disposition"])
    assert_equal "N12345", Zip::File.open(path) { JSON.parse(_1.read("manifest.json")) }["aircraft"]["tail_number"]
    assert_equal "Aircraft exported (.sam.zip)", @a.events.last.event_name
  end

  test "a records package imports from the .sam.zip inside it" do
    package = File.join(Dir.mktmpdir, "n12345-records.zip")
    RecordsPackage.new(@a, source: "test").write_to(package)
    assert_equal "N12345", AircraftArchive::Importer.check(package).tail_number
    copy = AircraftArchive::Importer.new(package, owner: @owner, tail_number: "N54321").run[:aircraft]
    assert_equal @a.logbook_entries.count, copy.logbook_entries.count
  end

  test "an archive re-zipped from an unzipped folder still imports" do
    sign_in @owner
    path = download_export
    rezipped = File.join(Dir.mktmpdir, "n12345.zip")
    Zip::File.open(path) do |src|
      Zip::OutputStream.open(rezipped) do |out|
        out.put_next_entry("__MACOSX/n12345/._manifest.json")
        out.write("resource fork")
        src.each do |e|
          next if e.directory?
          out.put_next_entry("n12345-export/#{e.name}")
          out.write(e.get_input_stream.read)
        end
      end
    end
    assert_equal "N12345", AircraftArchive::Importer.check(rezipped).tail_number
    copy = AircraftArchive::Importer.new(rezipped, owner: @owner, tail_number: "N54321").run[:aircraft]
    assert_equal @a.logbook_entries.count, copy.logbook_entries.count
    assert_equal @a.documents.count, copy.documents.count
  end

  test "importing an archive: tail clash asks for a new tail, then the job builds the aircraft" do
    sign_in @owner
    path = download_export
    archive = -> { Rack::Test::UploadedFile.new(path, "application/zip", original_filename: "n12345.sam.zip") }

    sign_in @pilot
    get root_path
    assert_select "a[href='#{new_aircraft_import_path}']"
    post aircraft_imports_path, params: { archive: archive.() }
    assert_response :unprocessable_entity
    assert_includes response.body, "An aircraft N12345 already exists"
    assert_equal 0, AircraftImport.count

    assert_enqueued_jobs 1, only: AircraftImportJob do
      post aircraft_imports_path, params: { archive: archive.(), tail_number: "n54321" }
    end
    import = AircraftImport.last
    assert_redirected_to aircraft_import_path(import)
    assert_equal [ "N54321", @pilot, "queued" ], [ import.tail_number, import.user, import.status ]
    follow_redirect!
    assert_includes response.body, "Waiting to start"
    assert_select "meta[http-equiv=refresh]"

    perform_enqueued_jobs(only: AircraftImportJob)
    import.reload
    assert_equal "done", import.status, import.error
    copy = import.aircraft
    assert_equal [ "N54321", "Cessna" ], [ copy.tail_number, copy.make ]
    assert_equal [ "owner" ], copy.roles.where(user: @pilot).pluck(:role) # the importer owns the copy
    assert_equal "notes.txt", copy.squawks.sole.attachments.sole.filename.to_s
    assert_equal 1, import.counts["logbook_entries"]

    get aircraft_import_path(import)
    assert_includes response.body, "Imported."
    assert_select "meta[http-equiv=refresh]", 0
    assert_select "a[href='#{aircraft_path(copy)}']"
    perform_enqueued_jobs # purge the staged archive
    refute import.reload.archive.attached?

    sign_in create_user
    get aircraft_import_path(import)
    assert_response :not_found # only the importer (or an admin) sees it
  end

  test "a bad file is refused up front" do
    sign_in @owner
    post aircraft_imports_path, params: { archive: fixture_file_upload("flights.csv", "application/zip") }
    assert_redirected_to new_aircraft_import_path
    assert_match "That archive can't be imported: Not a valid .sam.zip archive", flash[:alert]
  end
end

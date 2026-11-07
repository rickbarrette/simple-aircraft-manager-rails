require "test_helper"

class LogbookImportFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Stands in for Anthropic::Client: records each request and answers from a queue.
  class FakeClaude
    Message = Struct.new(:stop_reason, :content, :model)
    Text = Struct.new(:type, :text)
    attr_reader :requests

    def initialize(*answers)
      @answers = answers
      @requests = []
    end

    def beta = self
    def messages = self

    def stream(**params)
      @requests << params
      answer = @answers.shift or raise "unexpected request"
      message = answer.is_a?(Symbol) ? Message.new(answer, [], "claude-opus-5-5") : Message.new(:end_turn, [ Text.new(:text, answer.to_json) ], "claude-opus-5-5")
      Struct.new(:accumulated_message).new(message)
    end
  end

  JPEG = "\xFF\xD8\xFF\xE0fake-jpeg".b

  def entry(text, page_start, page_end = page_start, **extra)
    { date: "2026-01-05", log_type: "ENG", entry_type: "MAINTENANCE", text: text, aircraft_hours: 1990.5,
      signoff_person: "J. Mechanic", signoff_location: "KOQU", signoff_certificate_type: "AP",
      signoff_certificate_number: "1234567", page_start: page_start, page_end: page_end,
      confidence: "high" }.merge(extra)
  end

  def answer(*entries, forms: []) = { entries: entries, non_logbook_pages: forms, unparseable_pages: [] }

  def page(name) = Rack::Test::UploadedFile.new(StringIO.new(JPEG), "image/jpeg", original_filename: name)

  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot)
    @previous_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "sk-ant-test"
    LogbookTranscriptionJob.batch_pages = 2
  end

  teardown do
    ENV["ANTHROPIC_API_KEY"] = @previous_key
    LogbookTranscriber.client = nil
    LogbookTranscriptionJob.batch_pages = 6
  end

  test "pages are saved in name order and transcribed in overlapping batches" do
    claude = FakeClaude.new(
      # pages 1–2: A on page 1; B starts on page 2 and may continue
      answer(entry("Changed oil", 0), entry("Annual inspection, found", 1, 1, entry_type: "INSPECTION")),
      # pages 2–3: B completed from the carried copy, C on page 3 (no readable date, hard to read), page 3 also has a form
      answer(entry("Annual inspection, found airworthy", 0, 1, entry_type: "INSPECTION"), entry("Replaced [?] gasket", 1, date: nil, confidence: "low"))
    )
    LogbookTranscriber.client = claude
    sign_in @owner

    get aircraft_logbook_entries_path(@a)
    assert_select "a[href='#{new_aircraft_logbook_import_path(@a)}']", text: "Import scans"
    get new_aircraft_logbook_import_path(@a)
    assert_select "input[type=checkbox][name=transcribe]:not([disabled])"

    post aircraft_logbook_imports_path(@a), params: { pages: [ page("page-10.jpg"), page("page-2.jpg"), page("page-1.jpg") ],
                                                      collection_id: "new", collection_name: "Engine Log #1", transcribe: "1", log_type: "" }
    import = @a.logbook_imports.last
    assert_redirected_to aircraft_logbook_import_path(@a, import)
    document = import.document
    assert_equal %w[page-1.jpg page-2.jpg page-10.jpg], document.pages.sort_by(&:id).map { _1.filename.to_s } # natural order
    assert_equal "Engine Log #1", document.document_collection.name
    assert_equal "LOG", document.doc_type

    follow_redirect!
    assert_select "meta[http-equiv=refresh]"
    perform_enqueued_jobs(only: LogbookTranscriptionJob)
    import.reload
    assert_equal [ "done", 3, 3, 3 ], [ import.status, import.pages_total, import.pages_done, import.entries_created ], import.error

    first, second = claude.requests
    assert_equal "claude-opus-5-5", first[:model]
    assert_equal :default, first[:fallbacks]
    assert_equal [ "server-side-fallback-2026-07-01" ], first[:betas]
    assert_equal :json_schema, first[:output_config][:format_][:type]
    assert_equal 2, first[:messages][0][:content].count { _1[:type] == "image" }
    assert_match "Entries already read from page 0", second[:messages][0][:content].map { _1[:text] }.compact.join
    assert_match "Annual inspection, found", second[:messages][0][:content].map { _1[:text] }.compact.join

    entries = @a.logbook_entries.order(:id)
    assert_equal [ "Changed oil", "Annual inspection, found airworthy", "[date unreadable] Replaced [?] gasket" ], entries.map(&:text)
    assert entries.none?(&:verified?) # transcriptions wait for a person to check them
    assert_equal [ "high", "high", "low" ], entries.map(&:transcription_confidence)
    assert_equal [ "J. Mechanic", "AP", "1234567" ], entries.first.then { [ _1.signoff_person, _1.signoff_certificate_type, _1.signoff_certificate_number ] }
    assert_equal [ 1, 2, 3 ], entries.map(&:page_number)
    assert entries.all? { _1.document == document && _1.log_type == "ENG" }
    assert_equal [ "MAINTENANCE", "INSPECTION", "MAINTENANCE" ], entries.map(&:entry_type)
    assert_equal 1990.5, entries.first.aircraft_hours_at_entry.to_f
    assert_equal Date.new(2026, 1, 5), entries.last.date # borrowed from the entry before it
    assert_equal 2, import.warnings.size
    assert_match "had no readable date", import.warnings.first
    assert_match "hard to read", import.warnings.last

    get aircraft_logbook_import_path(@a, import)
    assert_includes response.body, "Done: 3 logbook entries added."
    assert_select "meta[http-equiv=refresh]", 0
    assert_equal "Logbook pages transcribed (3 entries)", @a.events.where(category: "logbook").last.event_name
  end

  test "a PDF goes up whole, the log type can be forced, and a refusal becomes a note" do
    LogbookTranscriber.client = FakeClaude.new(answer(entry("Prop overhauled", 0), entry("Prop balanced", 2, log_type: "AC"), forms: [ 1 ]), :refusal)
    sign_in @owner
    pdf = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 fake"), "application/pdf", original_filename: "prop-log.pdf")
    post aircraft_logbook_imports_path(@a), params: { pages: [ page("z-loose-page.jpg"), pdf ], transcribe: "1", log_type: "PROP",
                                                      collection_id: "new", document_name: "Prop log" }
    perform_enqueued_jobs(only: LogbookTranscriptionJob)
    import = @a.logbook_imports.last
    assert_equal "done", import.status
    request = LogbookTranscriber.client.requests.first
    assert_equal [ "text", "document", "text" ], request[:messages][0][:content].map { _1[:type] }
    assert_equal %w[PROP PROP], @a.logbook_entries.pluck(:log_type)
    assert_equal [ 1, 1 ], @a.logbook_entries.pluck(:page_number) # both from the PDF, page 1 of the document
    assert_match "Not logbook entries (forms, tags…), so nothing was transcribed from: prop-log.pdf page 2", import.warnings.first
    assert_equal "Page 2 wasn't transcribed: Claude declined to read these pages.", import.warnings.last
  end

  test "without an API key, pages are only uploaded" do
    ENV["ANTHROPIC_API_KEY"] = nil
    LogbookTranscriber.client = FakeClaude.new # any request would raise
    sign_in @owner
    get new_aircraft_logbook_import_path(@a)
    assert_select "input[type=checkbox][name=transcribe][disabled]"
    assert_includes response.body, "ANTHROPIC_API_KEY"
    post aircraft_logbook_imports_path(@a), params: { pages: [ page("p1.jpg") ], transcribe: "1", collection_id: "new" }
    perform_enqueued_jobs(only: LogbookTranscriptionJob)
    import = @a.logbook_imports.last
    assert_equal [ "done", false, 0 ], [ import.status, import.transcribe, import.entries_created ]
    assert_equal 1, import.document.pages.count
  end

  test "rejects files that aren't scans, and pilots can't import" do
    sign_in @owner
    post aircraft_logbook_imports_path(@a), params: { pages: [ fixture_file_upload("engine_data/cgr30p.csv", "application/x-msdownload") ], collection_id: "new" }
    assert_response :unprocessable_entity
    assert_equal 0, @a.documents.count

    sign_in @pilot
    get new_aircraft_logbook_import_path(@a)
    assert_redirected_to aircraft_path(@a)
  end
end

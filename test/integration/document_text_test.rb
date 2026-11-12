require "test_helper"
require "prawn"

# Text inside documents, read for search: PDF text, OCR for scans, or Claude.
class DocumentTextTest < ActionDispatch::IntegrationTest
  class FakeClaude
    Message = Struct.new(:stop_reason, :content, :model)
    Text = Struct.new(:type, :text)
    attr_reader :requests

    def initialize(text) = (@text = text; @requests = [])
    def beta = self
    def messages = self

    def stream(**params)
      @requests << params
      Struct.new(:accumulated_message).new(Message.new(:end_turn, [ Text.new(:text, @text) ], "claude-opus-5-5"))
    end
  end

  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    @dir = Dir.mktmpdir
  end

  teardown { FileUtils.rm_rf(@dir) }

  def text_pdf(text)
    path = File.join(@dir, "text-#{SecureRandom.hex(3)}.pdf")
    Prawn::Document.generate(path) { |pdf| pdf.font_size(28) { pdf.text text } }
    path
  end

  # A page with no text layer: a picture of text, as a scanner makes.
  def scan_png(text)
    pdf = text_pdf(text)
    system("pdftoppm", "-r", "150", "-png", "-singlefile", pdf, File.join(@dir, "scan")) or skip "pdftoppm not installed"
    File.join(@dir, "scan.png")
  end

  def document(path, type)
    doc = @a.documents.create!(name: File.basename(path), doc_type: "INVOICE")
    doc.pages.attach(io: File.open(path, "rb"), filename: File.basename(path), content_type: type)
    doc
  end

  test "a PDF's own text is read, and search finds it" do
    doc = document(text_pdf("Magneto timing set to 22 degrees BTC"), "application/pdf")
    perform_enqueued_jobs { DocumentTextJob.perform_now(doc.id) }
    doc.reload
    assert_equal "text", doc.pages_text_method
    assert_includes doc.pages_text, "Magneto timing"
    refute doc.pages_text_stale?
    assert_no_difference("RecordVersion.count") { DocumentTextJob.perform_now(doc.id) } # derived text isn't a record change

    sign_in @owner
    get search_path(q: "timing set")
    assert_select "h2", text: /Documents/
    assert_select "mark", text: /timing set/i
  end

  test "a scan is read with Tesseract, and a scanned PDF too" do
    skip "tesseract not installed" unless DocumentText.tesseract?
    image = document(scan_png("ALTERNATOR REPLACED"), "image/png")
    DocumentTextJob.perform_now(image.id)
    assert_equal "ocr", image.reload.pages_text_method
    assert_match(/ALTERNATOR/i, image.pages_text)

    scanned_pdf = File.join(@dir, "scanned.pdf")
    png = scan_png("VACUUM PUMP INSPECTED")
    Prawn::Document.generate(scanned_pdf) { |pdf| pdf.image png, fit: [ 500, 700 ] }
    doc = document(scanned_pdf, "application/pdf")
    DocumentTextJob.perform_now(doc.id)
    assert_equal "ocr", doc.reload.pages_text_method
    assert_match(/VACUUM/i, doc.pages_text)
  end

  test "with Claude turned on and a key set, scans go to Claude; the nightly run catches up" do
    Setting.create!(key: "documents_claude_text", value: "1")
    claude = FakeClaude.new("Starter replaced, Sky example S/N 10000000")
    LogbookTranscriber.client = claude
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    doc = document(scan_png("anything"), "image/png")
    doc.update_columns(pages_text_source: nil)
    DocumentTextJob.perform_now # nightly: finds documents not read yet
    assert_equal [ "claude", "Starter replaced, Sky example S/N 10000000" ], doc.reload.slice(:pages_text_method, :pages_text).values
    request = claude.requests.sole
    assert_equal :default, request[:fallbacks]
    assert_equal "image", request[:messages].first[:content].first[:type]
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
    LogbookTranscriber.client = nil
  end
end

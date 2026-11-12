require "open3"
require "anthropic"

# Reads the text on a document's pages so search can find it: a PDF's own
# text where it has one, otherwise OCR. OCR is Tesseract (free, local, good on
# print, poor on handwriting) unless an admin turned on reading scans with
# Claude (Settings) and an Anthropic API key is set.
class DocumentText
  MAX_CHARS = 300_000
  MAX_PAGES = 40            # per file, for OCR
  SCANNED = 30              # fewer characters a page than this: treat a PDF as scanned
  CLAUDE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  Result = Data.define(:text, :method)

  def self.tesseract? = system("which tesseract >/dev/null 2>&1")
  def self.pdftoppm? = system("which pdftoppm >/dev/null 2>&1")
  def self.claude? = Setting.integer("documents_claude_text") == 1 && ENV["ANTHROPIC_API_KEY"].present?

  def initialize(document)
    @document = document
  end

  def read
    texts = []
    methods = []
    @document.pages.each do |page|
      text, method = read_page(page)
      texts << text if text.present?
      methods << method
    end
    method = methods.include?("claude") ? "claude" : (methods.include?("ocr") ? "ocr" : (methods.include?("text") ? "text" : "none"))
    Result.new(text: texts.join("\n\n").squeeze(" \n").first(MAX_CHARS), method: method)
  end

  private

  def read_page(page)
    type = page.blob.content_type.to_s
    page.blob.open do |file|
      if type == "application/pdf" then read_pdf(file.path, page.blob.byte_size)
      elsif type.start_with?("text/") then [ File.read(file.path, MAX_CHARS).to_s.scrub, "text" ]
      elsif type.start_with?("image/") then scan_image(file.path, type, page.blob.byte_size)
      else [ nil, "none" ]
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[document text] #{@document.id} #{page.filename}: #{e.class}: #{e.message}")
    [ nil, "none" ]
  end

  def read_pdf(path, bytes)
    reader = PDF::Reader.new(path)
    pages = reader.pages.first(500).map { _1.text.to_s }
    text = pages.join("\n").squeeze(" ")
    return [ text, "text" ] if pages.empty? || text.gsub(/\s/, "").length >= SCANNED * pages.size
    scan_pdf(path, bytes) # little or no text layer: it's a scan
  end

  def scan_pdf(path, bytes)
    return claude([ { data: File.binread(path), media_type: "application/pdf" } ]) if self.class.claude? && bytes <= LogbookTranscriber::MAX_PDF_BYTES
    return [ nil, "none" ] unless self.class.pdftoppm? && self.class.tesseract?
    Dir.mktmpdir("sam-ocr") do |dir|
      _, status = Open3.capture2e("timeout", "300", "pdftoppm", "-r", "150", "-png", "-f", "1", "-l", MAX_PAGES.to_s, path, File.join(dir, "p"))
      return [ nil, "none" ] unless status.success?
      text = Dir[File.join(dir, "p*.png")].sort.map { tesseract(_1) }.compact.join("\n")
      [ text, "ocr" ]
    end
  end

  def scan_image(path, type, bytes)
    if self.class.claude? && CLAUDE_TYPES.include?(type) && bytes <= LogbookTranscriber::MAX_IMAGE_BYTES
      claude([ { data: File.binread(path), media_type: type } ])
    elsif self.class.tesseract?
      [ tesseract(path), "ocr" ]
    else
      [ nil, "none" ]
    end
  end

  def tesseract(path)
    out, status = Open3.capture2("timeout", "120", "tesseract", path, "stdout", "-l", "eng", err: File::NULL)
    status.success? ? out : nil
  end

  # Claude reads the scan (handwriting too). Uses the same model and settings
  # as logbook transcription.
  def claude(files)
    blocks = files.map do |f|
      kind = f[:media_type] == "application/pdf" ? "document" : "image"
      { type: kind, source: { type: "base64", media_type: f[:media_type], data: Base64.strict_encode64(f[:data]) } }
    end
    stream = LogbookTranscriber.client.beta.messages.stream(
      model: LogbookTranscriber::MODEL,
      max_tokens: 64_000,
      output_config: { effort: :low },
      fallbacks: :default,
      betas: [ LogbookTranscriber::FALLBACK_BETA ],
      messages: [ { role: "user", content: blocks + [ { type: "text", text: "Transcribe all the text in this document, in reading order, as plain text. Include handwriting. Output only the text." } ] } ]
    )
    message = stream.accumulated_message
    return [ nil, "none" ] if message.stop_reason == :refusal
    [ message.content.select { _1.type == :text }.map(&:text).join, "claude" ]
  rescue Anthropic::Errors::APIError => e
    Rails.logger.warn("[document text] Claude: #{e.class}: #{e.message}")
    [ nil, "none" ]
  end
end

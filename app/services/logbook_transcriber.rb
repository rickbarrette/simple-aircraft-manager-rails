require "anthropic"

# Reads scanned logbook pages with Claude and returns the entries on them.
# One call handles one batch: several page images, or one PDF.
#
#   LogbookTranscriber.new.transcribe([ { data: bytes, media_type: "image/jpeg" }, … ], carried: [...])
#
# `carried` are entries already read from page 0 of this batch (the last page of
# the previous one), so an entry continuing onto the next page is completed
# rather than duplicated.
class LogbookTranscriber
  class Error < StandardError; end

  MODEL = ENV.fetch("LOGBOOK_AI_MODEL", "claude-opus-5-5")
  EFFORT = ENV.fetch("LOGBOOK_AI_EFFORT", "high") # handwriting rewards a careful read
  MAX_TOKENS = 64_000
  PROMPT = File.read(File.join(__dir__, "logbook_transcriber/prompt.txt")).freeze
  SCHEMA = JSON.parse(File.read(File.join(__dir__, "logbook_transcriber/schema.json"))).freeze
  FALLBACK_BETA = "server-side-fallback-2026-07-01"
  IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_IMAGE_BYTES = 5.megabytes # the API's per-image limit
  MAX_PDF_BYTES = 30.megabytes  # request limit is 32 MB

  Result = Struct.new(:entries, :non_logbook_pages, :unparseable_pages, :model, keyword_init: true)

  class << self
    attr_writer :client # tests swap in a fake

    def client = @client ||= Anthropic::Client.new
  end

  def initialize(client: self.class.client, model: MODEL, effort: EFFORT)
    @client = client
    @model = model
    @effort = effort
  end

  def transcribe(pages, carried: [])
    stream = @client.beta.messages.stream(
      model: @model,
      max_tokens: MAX_TOKENS,
      system_: PROMPT,
      output_config: { effort: @effort.to_sym, format_: { type: :json_schema, schema: SCHEMA } },
      # If a safety classifier declines, the API retries on its default substitute model.
      fallbacks: :default,
      betas: [ FALLBACK_BETA ],
      messages: [ { role: "user", content: content(pages, carried) } ]
    )
    message = stream.accumulated_message
    case message.stop_reason
    when :refusal then raise Error, I18n.t("services.logbook_transcriber.claude_declined_to_read_these")
    when :max_tokens then raise Error, I18n.t("services.logbook_transcriber.the_transcription_was_too_long")
    end

    text = message.content.select { _1.type == :text }.map(&:text).join
    data = JSON.parse(text)
    Result.new(entries: Array(data["entries"]), non_logbook_pages: Array(data["non_logbook_pages"]),
               unparseable_pages: Array(data["unparseable_pages"]), model: message.model.to_s)
  rescue JSON::ParserError
    raise Error, I18n.t("services.logbook_transcriber.claude_s_answer_wasn_t")
  rescue Anthropic::Errors::RateLimitError
    raise Error, I18n.t("services.logbook_transcriber.the_anthropic_api_is_rate")
  rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError
    raise Error, I18n.t("services.logbook_transcriber.the_anthropic_api_key_was")
  rescue Anthropic::Errors::APIStatusError => e
    raise Error, I18n.t("services.logbook_transcriber.the_anthropic_api_returned_an", status: e.status)
  rescue Anthropic::Errors::APIConnectionError
    raise Error, I18n.t("services.logbook_transcriber.couldn_t_reach_the_anthropic")
  end

  private

  def content(pages, carried)
    blocks = pages.each_with_index.flat_map do |page, i|
      source = { type: "base64", media_type: page[:media_type], data: Base64.strict_encode64(page[:data]) }
      if page[:media_type] == "application/pdf"
        [ { type: "text", text: "This PDF holds the logbook pages; page indices count its pages from 0." },
          { type: "document", source: source } ]
      else
        [ { type: "text", text: "Page #{i}:" }, { type: "image", source: source } ]
      end
    end
    if carried.any?
      context = carried.map do |e|
        "- #{e['date'] || 'undated'} (#{e['log_type']}, signed #{e['signoff_person'] || 'unsigned'}): #{e['text'].to_s.truncate(400)}"
      end
      blocks << { type: "text", text: "Entries already read from page 0 (it was the last page of the previous batch):\n#{context.join("\n")}" }
    end
    blocks << { type: "text", text: "Extract every logbook entry from these pages." }
  end
end

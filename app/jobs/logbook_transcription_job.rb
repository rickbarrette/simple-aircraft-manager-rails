# Transcribes an uploaded logbook document into LogbookEntry records with
# Claude (LogbookTranscriber).
#
# Images go up in batches of a few pages. Consecutive batches overlap by one
# page so an entry running onto the next page is read whole: entries seen on a
# batch's last page are held back and handed to the next batch, which returns
# them completed. Each PDF goes up as one request.
class LogbookTranscriptionJob < ApplicationJob
  queue_as :default

  class_attribute :batch_pages, default: 6
  BATCH_BYTES = 18.megabytes # base64 grows this by a third; requests cap at 32 MB

  def perform(import_id)
    @import = LogbookImport.find_by(id: import_id) or return
    return unless @import.status == "queued"

    @document = @import.document
    pages = @document ? @document.pages.attachments.includes(:blob).sort_by(&:id) : []
    @import.update!(status: "running", started_at: Time.current, pages_total: pages.size, model: (LogbookTranscriber::MODEL if @import.transcribe))
    transcribe(pages) if @import.transcribe && pages.any?
    finish
  rescue StandardError => e
    @import&.update!(status: "failed", finished_at: Time.current, error: "#{e.class}: #{e.message}".truncate(1000))
    Rails.logger.error("[logbook import] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
  end

  private

  def transcribe(pages)
    @transcriber = LogbookTranscriber.new
    @last_date = nil
    readable = pages.each_with_index.filter_map do |attachment, index|
      type = attachment.blob.content_type
      if type == "application/pdf"
        next warn("Page #{index + 1} (#{attachment.filename}) is over #{LogbookTranscriber::MAX_PDF_BYTES / 1.megabyte} MB, too large to transcribe.") if attachment.blob.byte_size > LogbookTranscriber::MAX_PDF_BYTES
      elsif !LogbookTranscriber::IMAGE_TYPES.include?(type)
        next warn("Page #{index + 1} (#{attachment.filename}) isn't a JPEG, PNG, GIF, WebP or PDF, so it wasn't transcribed.")
      elsif attachment.blob.byte_size > LogbookTranscriber::MAX_IMAGE_BYTES
        next warn("Page #{index + 1} (#{attachment.filename}) is over 5 MB, too large to transcribe. Scan it at a lower resolution.")
      end
      { attachment: attachment, number: index + 1, pdf: type == "application/pdf" }
    end
    tick(pages.size - readable.size)

    readable.slice_when { |a, b| a[:pdf] || b[:pdf] }.each do |run|
      run.first[:pdf] ? transcribe_pdf(run.first) : transcribe_images(run)
    end
  end

  def transcribe_pdf(page)
    result = @transcriber.transcribe([ payload(page) ])
    note_skipped(result, ->(i) { "#{page[:attachment].filename} page #{i + 1}" })
    result.entries.sort_by { _1["page_start"].to_i }.each { save(_1, page[:number]) }
  rescue LogbookTranscriber::Error => e
    warn("#{page[:attachment].filename} wasn't transcribed: #{e.message}.")
  ensure
    tick(1)
  end

  def transcribe_images(pages)
    batches = []
    start = 0
    while start < pages.size
      batch = [ pages[start] ]
      bytes = pages[start][:attachment].blob.byte_size
      while (nxt = pages[start + batch.size]) && batch.size < batch_pages && bytes + nxt[:attachment].blob.byte_size <= BATCH_BYTES
        batch << nxt
        bytes += nxt[:attachment].blob.byte_size
      end
      batches << batch
      break if start + batch.size >= pages.size
      start += [ batch.size - 1, 1 ].max # overlap by one page
    end

    held = [] # entries read from the previous batch's last page
    batches.each_with_index do |batch, n|
      last_batch = n == batches.size - 1
      begin
        result = @transcriber.transcribe(batch.map { payload(_1) }, carried: held.map { _1[:entry] })
      rescue LogbookTranscriber::Error => e
        held.each { save(_1[:entry], _1[:number]) } # keep what the previous batch read
        held = []
        pages = batch.size == 1 ? "Page #{batch.first[:number]} wasn't" : "Pages #{batch.first[:number]}–#{batch.last[:number]} weren't"
        warn("#{pages} transcribed: #{e.message}.")
        tick(n.zero? ? batch.size : batch.size - 1)
        next
      end
      note_skipped(result, ->(i) { "page #{batch[i]&.dig(:number) || '?'}" })

      entries = result.entries.sort_by { _1["page_start"].to_i }
      held = []
      entries.each do |entry|
        page = batch[entry["page_start"].to_i.clamp(0, batch.size - 1)]
        if !last_batch && entry["page_end"].to_i >= batch.size - 1
          held << { entry: entry, number: page[:number] } # may continue on the next batch
        else
          save(entry, page[:number])
        end
      end
      tick(n.zero? ? batch.size : batch.size - 1)
    end
    held.each { save(_1[:entry], _1[:number]) }
  end

  def payload(page)
    { data: page[:attachment].blob.download, media_type: page[:attachment].blob.content_type }
  end

  def save(entry, page_number)
    date = parse_date(entry["date"])
    text = entry["text"].to_s.strip.presence || "[no text read]"
    unless date
      text = "[date unreadable] #{text}"
      warn("An entry on page #{page_number} had no readable date#{@last_date ? "; it was given the previous entry's date (#{@last_date})" : ' and was dated today'}. Please check it.")
    end
    date ||= @last_date || Date.current
    @last_date = date
    log_type = @import.log_type || (LogbookEntry::LOG_TYPES.key?(entry["log_type"]) ? entry["log_type"] : "AC")
    @import.aircraft.logbook_entries.create!(
      date: date, text: text, log_type: log_type,
      entry_type: LogbookEntry::ENTRY_TYPES.key?(entry["entry_type"]) ? entry["entry_type"] : "OTHER",
      signoff_person: entry["signoff_person"].presence, signoff_location: entry["signoff_location"].presence,
      aircraft_hours_at_entry: entry["aircraft_hours"].is_a?(Numeric) && entry["aircraft_hours"] >= 0 ? entry["aircraft_hours"] : nil,
      document: @document, page_number: page_number
    )
    @import.increment!(:entries_created)
    warn("The #{date} entry on page #{page_number} was hard to read. Please check it against the scan.") if entry["confidence"] == "low"
  end

  def note_skipped(result, label)
    forms = result.non_logbook_pages.map { label.(_1) }
    unreadable = result.unparseable_pages.map { label.(_1) }
    warn("Not logbook entries (forms, tags…), so nothing was transcribed from: #{forms.uniq.to_sentence}.") if forms.any?
    warn("Too hard to read: #{unreadable.uniq.to_sentence}.") if unreadable.any?
  end

  def parse_date(value)
    date = Date.iso8601(value.to_s) if value.present?
    date if date && date.year > 1900 && date <= Date.current + 1.year
  rescue Date::Error
    nil
  end

  def warn(message)
    @import.warnings = @import.warnings + [ message ]
    @import.save!
    nil
  end

  def tick(pages)
    @import.update_columns(pages_done: [ @import.pages_done + pages, @import.pages_total ].min, updated_at: Time.current) if pages.positive?
  end

  def finish
    @import.update!(status: "done", finished_at: Time.current, pages_done: @import.pages_total)
    if @import.transcribe
      @import.aircraft.log_event!("logbook", "Logbook pages transcribed (#{@import.entries_created} entries)",
                                  notes: @document&.name, user: @import.user)
    end
  end
end

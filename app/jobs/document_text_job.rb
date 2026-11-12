# Reads a document's text for search after its pages change; the nightly run
# catches up documents that were never read (or changed since).
class DocumentTextJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "document_text", duration: 2.hours if respond_to?(:limits_concurrency)

  BATCH = 25

  def perform(document_id = nil)
    if document_id
      (doc = Document.find_by(id: document_id)) && read(doc)
    else
      Document.includes(pages_attachments: :blob).find_each.select { _1.pages_text_stale? }.first(BATCH).each { read(_1) }
    end
  end

  private

  def read(doc)
    return unless doc.pages_text_stale?
    result = DocumentText.new(doc).read
    # Derived search text: written directly, so it isn't a record change.
    doc.update_columns(pages_text: result.text.presence, pages_text_method: result.method,
                       pages_text_source: doc.pages_source_key, pages_text_at: Time.current)
  end
end

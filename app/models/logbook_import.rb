# Scanned logbook pages uploaded as a document, and (optionally) their
# transcription into logbook entries by Claude. See LogbookTranscriptionJob.
class LogbookImport < ApplicationRecord
  belongs_to :aircraft
  belongs_to :user, optional: true
  belongs_to :document, optional: true

  STATUSES = %w[queued running done failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :log_type, inclusion: { in: LogbookEntry::LOG_TYPES.keys }, allow_nil: true

  normalizes :log_type, with: ->(v) { v.presence }

  # Transcription needs an Anthropic API key in the environment.
  def self.ai_available? = ENV["ANTHROPIC_API_KEY"].present?

  def in_progress? = status.in?(%w[queued running])
  def done? = status == "done"
  def failed? = status == "failed"
  def progress_percent = pages_total.zero? ? 0 : (100.0 * pages_done / pages_total).round
end

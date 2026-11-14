# One upload of an aircraft archive (.sam.zip), imported by AircraftImportJob.
class AircraftImport < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :aircraft, optional: true
  has_one_attached :archive # staged upload; purged once imported

  STATUSES = %w[queued running done failed].freeze

  validates :status, inclusion: { in: STATUSES }

  def in_progress? = status.in?(%w[queued running])
  def done? = status == "done"
  def failed? = status == "failed"

  # "12 components, 140 logbook entries, …" for whatever was imported.
  def summary
    counts.select { |_, n| n.to_i.positive? }.map { |key, n| I18n.t(key, scope: "models.aircraft_import.counts", count: n.to_i) }.to_sentence
  end
end

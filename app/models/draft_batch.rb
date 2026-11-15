# One visit's work sent through the API as draft logbook entries: an
# unsigned entry for each logbook it touches, signed in the app like any
# other entry (by an aircraft user, or a mechanic invited to sign).
#
# What the work resolves (squawks, inspections) is held until every entry in
# the batch is signed: a draft never clears a squawk or completes an
# inspection on its own.
class DraftBatch < ApplicationRecord
  include Versioned

  STATUSES = %w[awaiting_signature completed withdrawn].freeze

  belongs_to :aircraft
  belongs_to :api_token, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :entries, class_name: "LogbookEntry", dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  def awaiting? = status == "awaiting_signature"

  def held_squawks = Array(held["squawks"])
  def held_inspections = Array(held["inspections"])

  # What signing will do, for the signer to see before they sign.
  def held_effects_for(entry)
    squawks = aircraft.squawks.where(id: held_squawks.select { _1["log"] == entry.log_type }.map { _1["id"] })
    types = aircraft.applicable_inspection_types.where(id: held_inspections.select { _1["log"] == entry.log_type }.map { _1["id"] })
    { squawks: squawks.to_a, inspections: types.to_a }
  end

  # Called when one of its entries is signed: once they all are, the held
  # changes are made, attributed to the person who signed last.
  def entry_signed!
    return unless awaiting?
    with_lock do
      return unless awaiting? && entries.reload.all?(&:signed?)
      by_log = entries.index_by(&:log_type)
      aircraft.squawks.active.where(id: held_squawks.map { _1["id"] }).find_each do |squawk|
        entry = by_log[held_squawks.find { _1["id"] == squawk.id }["log"]]
        squawk.resolve!(logbook_entry: entry)
        aircraft.log_event!("squawk", I18n.t("flash.squawks.squawk_resolved_2"), notes: squawk.issue_reported.truncate(200))
      end
      aircraft.applicable_inspection_types.where(id: held_inspections.map { _1["id"] }).find_each do |type|
        entry = by_log[held_inspections.find { _1["id"] == type.id }["log"]]
        aircraft.inspection_records.create!(inspection_type: type, logbook_entry: entry, date: entry.date, aircraft_hours: entry.aircraft_hours_at_entry)
        aircraft.log_event!("inspection", I18n.t("flash.logbook_entries.inspection_completed_logbook_entry",
                                                 name: type.name, date: I18n.l(entry.date, format: :app)))
      end
      update!(status: "completed", completed_at: Time.current)
    end
    Webhooks.publish("draft_batch.completed", aircraft: aircraft, data: ApiPresenter.draft_batch(self))
  end

  # Withdraws an unsigned batch: its entries are removed (kept in the record history).
  def withdraw!
    transaction do
      raise ActiveRecord::RecordInvalid, self if entries.any?(&:signed?)
      entries.each(&:destroy!)
      update!(status: "withdrawn")
    end
  end
end

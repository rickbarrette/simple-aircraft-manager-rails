class AdCompliance < ApplicationRecord
  belongs_to :airworthiness_directive
  belongs_to :aircraft, optional: true
  belongs_to :component, optional: true
  belongs_to :logbook_entry, optional: true
  belongs_to :inspection_record, optional: true

  validates :date_complied, :compliance_notes, presence: true
  validate { errors.add(:base, "Must belong to an aircraft or component") unless aircraft_id || component_id }
  validate :next_due_is_a_future_reading
  before_validation :fill_next_due, if: -> { next_due_at_time.to_d.zero? }

  scope :recent_first, -> { order(date_complied: :desc, created_at: :desc) }

  # Prefill next_due_at_time from the AD's hour recurrence (hours at compliance
  # + interval). Only fills a blank/zero value, so a typed-in reading wins.
  def fill_next_due
    return if permanent? || airworthiness_directive.nil?
    base = aircraft_hours_at_compliance || aircraft&.tach_time
    due = Compliance.next_due(airworthiness_directive.due_rule, date: date_complied, hours: base)
    self.next_due_at_time = due[:hours] if due[:hours]
  end

  def self.for_aircraft(aircraft)
    where(aircraft_id: aircraft.id).or(where(component_id: aircraft.components.select(:id)))
  end

  private

  # next_due_at_time is an absolute tach reading, not an interval. Catch the
  # easy mistake of entering "100" for "every 100 hours".
  def next_due_is_a_future_reading
    due = next_due_at_time.to_d
    return if permanent? || due <= 0
    base = aircraft_hours_at_compliance || aircraft&.tach_time
    return unless base && due <= base
    errors.add(:next_due_at_time, "must be a tach reading after the compliance hours (#{base}). " \
                                  "For “every 100 hours” enter #{base + 100}, not 100")
  end
end

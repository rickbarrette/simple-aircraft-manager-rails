class AdCompliance < ApplicationRecord
  include Versioned
  # Method of compliance, recorded per 91.417(a)(2)(v).
  METHODS = {
    "inspection" => "Inspection",
    "terminating" => "Terminating action (no further action)",
    "amoc" => "Alternative method of compliance (AMOC)",
    "not_applicable" => "Not applicable to this aircraft"
  }.freeze

  belongs_to :airworthiness_directive
  belongs_to :aircraft, optional: true
  belongs_to :component, optional: true
  belongs_to :logbook_entry, optional: true
  belongs_to :inspection_record, optional: true

  validates :date_complied, :compliance_notes, presence: true
  validates :compliance_method, inclusion: { in: METHODS.keys }
  before_validation :apply_method
  before_validation :fill_revision
  validate { errors.add(:base, "Must belong to an aircraft or component") unless aircraft_id || component_id }
  validate :next_due_is_a_future_reading
  before_validation :fill_next_due, if: -> { next_due_at_time.to_d.zero? }

  scope :recent_first, -> { order(date_complied: :desc, created_at: :desc) }

  # Prefill next_due_at_time from the AD's hour recurrence (hours at compliance
  # + interval). Only fills a blank/zero value, so a typed-in reading wins.
  def fill_next_due
    return if closed? || airworthiness_directive.nil?
    base = aircraft_hours_at_compliance || aircraft&.current_hours
    due = Compliance.next_due(airworthiness_directive.due_rule, date: date_complied, hours: base)
    self.next_due_at_time = due[:hours] if due[:hours]
  end

  def method_label = METHODS[compliance_method]

  # The method decides the closing flags (kept for archives shared with the
  # original app): terminating action is permanent, N/A is not applicable.
  def apply_method
    self.compliance_method ||= not_applicable? ? "not_applicable" : (permanent? ? "terminating" : "inspection")
    self.not_applicable = compliance_method == "not_applicable"
    self.permanent = true if compliance_method == "terminating"
  end

  # The AD number and revision date complied with, from the AD if left blank.
  def fill_revision
    return if ad_revision.present? || airworthiness_directive.nil?
    ad = airworthiness_directive
    self.ad_revision = [ ad.name, ("effective #{ad.effective_date.iso8601}" if ad.effective_date) ].compact.join(", ")
  end

  # Permanent compliance or a not-applicable determination: never due again.
  def closed? = permanent? || not_applicable?

  def self.for_aircraft(aircraft)
    where(aircraft_id: aircraft.id).or(where(component_id: aircraft.components.select(:id)))
  end

  private

  # next_due_at_time is an absolute clock reading, not an interval. Catch the
  # easy mistake of entering "100" for "every 100 hours".
  def next_due_is_a_future_reading
    due = next_due_at_time.to_d
    return if closed? || due <= 0
    base = aircraft_hours_at_compliance || aircraft&.current_hours
    return unless base && due <= base
    errors.add(:next_due_at_time, "must be a #{aircraft&.time_basis || 'tach'} reading after the compliance hours (#{base}). " \
                                  "For “every 100 hours” enter #{base + 100}, not 100")
  end
end

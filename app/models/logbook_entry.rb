class LogbookEntry < ApplicationRecord
  LOG_TYPES = { "AC" => "Aircraft", "ENG" => "Engine", "PROP" => "Propeller", "OTHER" => "Other" }.freeze
  ENTRY_TYPES = {
    "MAINTENANCE" => "Maintenance", "INSPECTION" => "Inspection", "FLIGHT" => "Flight",
    "HOURS_UPDATE" => "Hours Update", "OTHER" => "Other"
  }.freeze

  # Kind of certificate of the person approving return to service (43.9(a)(4)).
  CERTIFICATE_TYPES = {
    "AP" => "A&P mechanic", "IA" => "A&P with Inspection Authorization", "A" => "Mechanic, airframe only",
    "P" => "Mechanic, powerplant only", "REPAIR_STATION" => "Repair station", "REPAIRMAN" => "Repairman",
    "PILOT" => "Pilot (preventive maintenance)", "OTHER" => "Other"
  }.freeze
  # An inspection entry ends with one of these (43.11(a)(5)).
  INSPECTION_RESULTS = {
    "approved" => "Airworthy, approved for return to service",
    "discrepancies" => "Not approved: discrepancy list given to the owner"
  }.freeze
  # Entries that 43.9 / 43.11 set requirements for.
  RECORD_TYPES = %w[MAINTENANCE INSPECTION].freeze

  belongs_to :aircraft
  belongs_to :document, optional: true
  has_many :inspection_records, dependent: :nullify
  has_many :ad_compliances, dependent: :nullify

  validates :date, :text, presence: true
  validates :log_type, inclusion: { in: LOG_TYPES.keys }
  validates :entry_type, inclusion: { in: ENTRY_TYPES.keys }
  validates :signoff_certificate_type, inclusion: { in: CERTIFICATE_TYPES.keys }, allow_blank: true
  validates :inspection_result, inclusion: { in: INSPECTION_RESULTS.keys }, allow_blank: true
  normalizes :signoff_certificate_type, :inspection_result, :signoff_certificate_number, with: ->(v) { v.strip.presence }

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def self.search(q)
    return all if q.blank?
    term = "%#{sanitize_sql_like(q)}%"
    where("text LIKE :t OR signoff_person LIKE :t OR signoff_location LIKE :t", t: term)
  end

  def to_s = "#{date} — #{LOG_TYPES[log_type]}"
  def certificate_label = CERTIFICATE_TYPES[signoff_certificate_type]
  def inspection_result_label = INSPECTION_RESULTS[inspection_result]

  # What a maintenance (43.9) or inspection (43.11) entry is missing. Not
  # enforced: older and transcribed entries often lack these, and the signed
  # logbook is the record of truth. Shown so gaps can be filled in.
  def missing_record_items
    return [] unless RECORD_TYPES.include?(entry_type)
    missing = []
    missing << "description of the work" if text.blank?
    missing << "signer's name" if signoff_person.blank?
    missing << "kind of certificate" if signoff_certificate_type.blank?
    missing << "certificate number" if signoff_certificate_number.blank?
    if entry_type == "INSPECTION"
      missing << "aircraft time in service" if aircraft_hours_at_entry.blank?
      missing << "airworthiness result" if inspection_result.blank?
    end
    missing
  end
end

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
  # For engine / propeller logs: which one, and its times at this entry.
  belongs_to :component, optional: true
  # Sub-components it also covers (the oil filter on the engine…).
  has_many :parts, -> { includes(component: :component_type).order(:id) }, class_name: "LogbookEntryPart",
                   dependent: :destroy, autosave: true
  # Electronic signature (AC 120-78B): once signed the entry is locked; a
  # correction is a new entry that supersedes it (2.2.8).
  has_one :signature, class_name: "EntrySignature", dependent: :destroy
  has_many :signing_invitations, dependent: :destroy
  belongs_to :supersedes, class_name: "LogbookEntry", optional: true
  has_one :superseded_by, class_name: "LogbookEntry", foreign_key: :supersedes_id, inverse_of: :supersedes, dependent: :nullify
  has_many :inspection_records, dependent: :nullify
  has_many :ad_compliances, dependent: :nullify
  has_many :squawks, dependent: :nullify

  validates :date, :text, presence: true
  validates :log_type, inclusion: { in: LOG_TYPES.keys }
  validates :entry_type, inclusion: { in: ENTRY_TYPES.keys }
  validates :signoff_certificate_type, inclusion: { in: CERTIFICATE_TYPES.keys }, allow_blank: true
  validates :inspection_result, inclusion: { in: INSPECTION_RESULTS.keys }, allow_blank: true
  validates :component_hours_at_entry, :component_since_overhaul_at_entry, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  normalizes :signoff_certificate_type, :inspection_result, :signoff_certificate_number, with: ->(v) { v.strip.presence }

  # Fields that may still change on a signed entry: its link to a scanned
  # page, the transcription check, and being superseded by a correction.
  UNSIGNED_FIELDS = %w[document_id page_number verified superseded_at updated_at].freeze
  before_update :keep_signed_content
  before_destroy(prepend: true) { throw :abort if signed? && !destroyed_by_association }

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }
  scope :unverified, -> { where(verified: false) }

  def self.search(q)
    return all if q.blank?
    term = "%#{sanitize_sql_like(q)}%"
    where("text LIKE :t OR signoff_person LIKE :t OR signoff_location LIKE :t", t: term)
  end

  def to_s = "#{date} — #{LOG_TYPES[log_type]}"

  def signed? = signature.present?
  def superseded? = superseded_at.present?

  # What a signature covers: the entry's own content, in a fixed form, so
  # the fingerprint changes if anything in it does.
  def content_payload
    num = ->(v) { v.nil? ? nil : format("%.1f", v) }
    {
      "v" => 1, "id" => id, "aircraft_id" => aircraft_id, "date" => date&.iso8601, "log_type" => log_type, "entry_type" => entry_type,
      "text" => text.to_s, "airframe_hours" => num.(aircraft_hours_at_entry), "location" => signoff_location.to_s,
      "signer" => [ signoff_person.to_s, signoff_certificate_type.to_s, signoff_certificate_number.to_s ],
      "inspection_result" => inspection_result.to_s, "supersedes_id" => supersedes_id,
      "component" => component_id && [ component_id, num.(component_hours_at_entry), num.(component_since_overhaul_at_entry) ],
      "parts" => parts.reject(&:marked_for_destruction?).map { [ _1.component_id, num.(_1.hours_at_entry), num.(_1.since_overhaul_at_entry) ] }.sort_by { _1.first.to_i }
    }
  end

  def content_digest = OpenSSL::Digest::SHA256.hexdigest(content_payload.to_json)

  # Readable copy of what was signed, kept with the signature.
  def content_snapshot
    c = component
    {
      "aircraft" => { "tail_number" => aircraft.tail_number, "make" => aircraft.make, "model" => aircraft.model, "serial_number" => aircraft.serial_number },
      "date" => date&.iso8601, "log" => LOG_TYPES[log_type], "entry_type" => ENTRY_TYPES[entry_type], "text" => text,
      "airframe_total_time" => aircraft_hours_at_entry&.to_s, "time_basis" => aircraft.time_basis, "location" => signoff_location,
      "inspection_result" => inspection_result_label,
      "component" => c && { "type" => c.component_type&.name, "make" => c.manufacturer, "model" => c.model, "serial_number" => c.serial_number,
                            "total_time" => component_hours_at_entry&.to_s, "since_overhaul" => component_since_overhaul_at_entry&.to_s,
                            "since_label" => c.since_overhaul_abbreviation },
      "parts" => parts.map { |p| { "type" => p.component.component_type&.name, "model" => p.component.model, "serial_number" => p.component.serial_number,
                                   "total_time" => p.hours_at_entry&.to_s, "since" => p.since_overhaul_at_entry&.to_s } },
      "supersedes" => supersedes && { "date" => supersedes.date&.iso8601, "fingerprint" => supersedes.signature&.content_digest }
    }
  end

  # "an annual" / "a 100-hour": from a linked inspection record, else the text.
  def inspection_kind_phrase
    name = inspection_records.first&.inspection_type&.name.to_s.sub(/\s*\(.*\)\z/, "").sub(/\s*inspection\z/i, "").strip.downcase
    name = "annual" if name.empty? && text.to_s.match?(/annual/i)
    name = "100-hour" if name.empty? && text.to_s.match?(/100[- ]?h(ou)?r/i)
    return "a ______________" if name.empty?
    "#{name.match?(/\A[aeiou]/) ? 'an' : 'a'} #{name}"
  end

  # What the signer certifies, by the kind of entry and certificate.
  def certification_statement(certificate_kind)
    if entry_type == "INSPECTION"
      if inspection_result == "discrepancies"
        "I certify that this aircraft has been inspected in accordance with #{inspection_kind_phrase} inspection and a list of discrepancies " \
          "and unairworthy items dated #{date&.strftime('%b %-d, %Y')} has been provided for the aircraft owner or operator."
      else
        "I certify that this aircraft has been inspected in accordance with #{inspection_kind_phrase} inspection and was determined to be in airworthy condition."
      end
    elsif certificate_kind == "PILOT"
      "I certify that the preventive maintenance described in this entry was performed in accordance with 14 CFR Part 43, and I approve it for return to service."
    elsif entry_type == "MAINTENANCE"
      "I certify that the work described in this entry was performed in accordance with 14 CFR Part 43, and I approve it for return to service with respect to that work."
    else
      "I certify that this entry is correct."
    end
  end

  # Why this certificate can't sign this entry ([] if it can).
  def signing_problems(certificate)
    problems = []
    problems << "it's already signed" if signed?
    problems << "it has been superseded by a correction" if superseded?
    problems << "it has no description" if text.blank?
    problems << "it has no date" if date.blank?
    if entry_type == "INSPECTION"
      problems << "an inspection entry needs its result (airworthy, or discrepancy list)" if inspection_result.blank?
      problems << "an inspection entry needs the aircraft's total time" if aircraft_hours_at_entry.blank?
    end
    if certificate
      problems << "that certificate has expired" if certificate.expired?
      problems << "a pilot certificate can sign preventive maintenance only" if certificate.kind == "PILOT" && entry_type != "MAINTENANCE"
      problems << "\"Other\" certificates can't sign maintenance or inspections" if certificate.kind == "OTHER" && RECORD_TYPES.include?(entry_type)
    else
      problems << "choose a certificate to sign with"
    end
    problems
  end

  # From the form: { component_id => { "include" => "1", "hours" => …, "since" => … } }.
  # Only the aircraft's sub-components of the entry's component are kept.
  def assign_parts(params, aircraft)
    allowed = component ? component.descendant_ids.to_set & aircraft.component_ids.to_set : Set.new
    wanted = params.to_h.select { |id, p| p["include"] == "1" && allowed.include?(id.to_i) }
    parts.each { |part| part.mark_for_destruction unless wanted.key?(part.component_id.to_s) }
    wanted.each do |id, p|
      part = parts.find { _1.component_id == id.to_i } || parts.build(component_id: id.to_i)
      part.assign_attributes(hours_at_entry: p["hours"].presence, since_overhaul_at_entry: p["since"].presence)
    end
  end
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

  private

  def keep_signed_content
    return unless signed? && signature.persisted?
    locked = changed - UNSIGNED_FIELDS
    return if locked.empty?
    errors.add(:base, "This entry is signed, so it can't be changed. Make a correction entry instead")
    throw :abort
  end
end

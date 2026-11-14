class LogbookEntry < ApplicationRecord
  include Versioned
  LOG_TYPES = LabelSet.new("logbook_entry.log_types", %w[AC ENG PROP OTHER])
  ENTRY_TYPES = LabelSet.new("logbook_entry.entry_types", %w[MAINTENANCE INSPECTION FLIGHT HOURS_UPDATE OTHER])

  # Kind of certificate of the person approving return to service (43.9(a)(4)).
  CERTIFICATE_TYPES = LabelSet.new("logbook_entry.certificate_types", %w[AP IA A P REPAIR_STATION REPAIRMAN PILOT OTHER])
  # An inspection entry ends with one of these (43.11(a)(5)).
  INSPECTION_RESULTS = LabelSet.new("logbook_entry.inspection_results", %w[approved discrepancies])
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

  def to_s = "#{date && I18n.l(date, format: :app)} — #{LOG_TYPES[log_type]}"

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
    return I18n.t("models.logbook_entry.inspection_blank") if name.empty?
    I18n.t(name.match?(/\A[aeiou]/) ? "models.logbook_entry.inspection_an" : "models.logbook_entry.inspection_a", name: name)
  end

  # What the signer certifies, by the kind of entry and certificate.
  def certification_statement(certificate_kind)
    if entry_type == "INSPECTION"
      if inspection_result == "discrepancies"
        I18n.t("models.logbook_entry.statements.discrepancies", inspection: inspection_kind_phrase, date: date && I18n.l(date, format: :app))
      else
        I18n.t("models.logbook_entry.statements.airworthy", inspection: inspection_kind_phrase)
      end
    elsif certificate_kind == "PILOT"
      I18n.t("models.logbook_entry.statements.preventive")
    elsif entry_type == "MAINTENANCE"
      I18n.t("models.logbook_entry.statements.maintenance")
    else
      I18n.t("models.logbook_entry.statements.other")
    end
  end

  # Why this certificate can't sign this entry ([] if it can).
  def signing_problems(certificate)
    problems = []
    problems << I18n.t("models.logbook_entry.signing_problems.already_signed") if signed?
    problems << I18n.t("models.logbook_entry.signing_problems.superseded") if superseded?
    problems << I18n.t("models.logbook_entry.signing_problems.no_description") if text.blank?
    problems << I18n.t("models.logbook_entry.signing_problems.no_date") if date.blank?
    if entry_type == "INSPECTION"
      problems << I18n.t("models.logbook_entry.signing_problems.no_result") if inspection_result.blank?
      problems << I18n.t("models.logbook_entry.signing_problems.no_total_time") if aircraft_hours_at_entry.blank?
    end
    if certificate
      problems << I18n.t("models.logbook_entry.signing_problems.certificate_expired") if certificate.expired?
      problems << I18n.t("models.logbook_entry.signing_problems.pilot_preventive_only") if certificate.kind == "PILOT" && entry_type != "MAINTENANCE"
      problems << I18n.t("models.logbook_entry.signing_problems.other_certificate") if certificate.kind == "OTHER" && RECORD_TYPES.include?(entry_type)
    else
      problems << I18n.t("models.logbook_entry.signing_problems.choose_certificate")
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
    missing << I18n.t("models.logbook_entry.missing.description") if text.blank?
    missing << I18n.t("models.logbook_entry.missing.signer") if signoff_person.blank?
    missing << I18n.t("models.logbook_entry.missing.certificate_kind") if signoff_certificate_type.blank?
    missing << I18n.t("models.logbook_entry.missing.certificate_number") if signoff_certificate_number.blank?
    if entry_type == "INSPECTION"
      missing << I18n.t("models.logbook_entry.missing.time_in_service") if aircraft_hours_at_entry.blank?
      missing << I18n.t("models.logbook_entry.missing.result") if inspection_result.blank?
    end
    missing
  end

  private

  def keep_signed_content
    return unless signed? && signature.persisted?
    locked = changed - UNSIGNED_FIELDS
    return if locked.empty?
    errors.add(:base, :signed_locked)
    throw :abort
  end
end

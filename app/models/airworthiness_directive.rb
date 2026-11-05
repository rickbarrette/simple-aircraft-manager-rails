class AirworthinessDirective < ApplicationRecord
  COMPLIANCE_TYPES = { "standard" => "Standard", "conditional" => "Conditional" }.freeze
  BULLETIN_TYPES = {
    "ad" => "Airworthiness Directive", "saib" => "Special Airworthiness Information Bulletin",
    "sb" => "Service Bulletin", "alert" => "Airworthiness Alert", "other" => "Other"
  }.freeze
  BULLETIN_LABELS = { "ad" => "AD", "saib" => "SAIB", "sb" => "SB", "alert" => "Alert", "other" => "Bulletin" }.freeze

  belongs_to :document, optional: true
  has_and_belongs_to_many :aircraft
  has_and_belongs_to_many :components
  has_many :ad_compliances, dependent: :destroy

  validates :name, :short_description, presence: true
  validates :compliance_type, inclusion: { in: COMPLIANCE_TYPES.keys }
  validates :bulletin_type, inclusion: { in: BULLETIN_TYPES.keys }
  validates :document_url, format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) link" }, allow_blank: true
  normalizes :document_url, with: ->(url) { url.strip.presence }

  scope :ordered, -> { order(:name) }

  # "2009-10-09  r2" → "2009-10-09 R2"
  def self.normalize_number(number)
    number.to_s.strip.upcase.gsub(/\s+/, " ")
  end

  def self.find_by_number(number)
    find_by("upper(replace(name, ' ', '')) = ?", normalize_number(number).delete(" "))
  end

  def self.applicable_to(aircraft)
    direct = joins(:aircraft).where(aircraft: { id: aircraft.id }).select(:id)
    via_component = joins(:components).where(components: { aircraft_id: aircraft.id }).select(:id)
    where(id: direct).or(where(id: via_component))
  end

  def to_s = name

  # [url, label] for this AD's document, when we have its link (DRS Excel
  # exports carry one per AD; it can also be pasted in). DRS links use an
  # internal document id, so they can't be derived from the AD number.
  def reference_link
    [ document_url, "View AD" ] if document_url.present?
  end

  def conditional? = compliance_type == "conditional"
  def bulletin_label = BULLETIN_LABELS[bulletin_type]

  # Recurrence rule for next-due math (AD status uses hours and months).
  def due_rule
    { hours: recurring_hours.to_f, months: recurring_months, days: 0 } if recurring?
  end

  def latest_compliance_for(aircraft)
    ad_compliances.for_aircraft(aircraft).order(date_complied: :desc, created_at: :desc).first
  end
end

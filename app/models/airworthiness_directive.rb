class AirworthinessDirective < ApplicationRecord
  COMPLIANCE_TYPES = LabelSet.new("airworthiness_directive.compliance_types", %w[standard conditional])
  BULLETIN_TYPES = LabelSet.new("airworthiness_directive.bulletin_types", %w[ad saib sb alert other])
  BULLETIN_LABELS = LabelSet.new("airworthiness_directive.bulletin_labels", %w[ad saib sb alert other])

  include CalendarInterval
  calendar_interval :recurring, days: :recurring_days, months: :recurring_months, blank: 0

  belongs_to :document, optional: true
  include SharedRecordHistory # has_and_belongs_to_many :aircraft and :components, with history
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

  def to_s = name

  # [url, label] for this AD's document, when we have its link (DRS Excel
  # exports carry one per AD; it can also be pasted in). DRS links use an
  # internal document id, so they can't be derived from the AD number.
  def reference_link
    [ document_url, I18n.t("models.airworthiness_directive.view") ] if document_url.present?
  end

  def conditional? = compliance_type == "conditional"
  def bulletin_label = BULLETIN_LABELS[bulletin_type]

  # Recurrence rule for next-due math.
  def due_rule
    { hours: recurring_hours.to_f, months: recurring_months, days: recurring_days } if recurring?
  end

  def latest_compliance_for(aircraft)
    ad_compliances.for_aircraft(aircraft).order(date_complied: :desc, created_at: :desc).first
  end
end

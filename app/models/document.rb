class Document < ApplicationRecord
  include Versioned
  include UploadValidation

  TYPES = {
    "LOG" => "Logbook", "ALTER" => "Alteration Record", "REPORT" => "Report",
    "ESTIMATE" => "Estimate", "DISC" => "Discrepancy List", "INVOICE" => "Receipt / Invoice",
    "AIRCRAFT" => "Aircraft Record", "REGISTRATION" => "Registration Certificate",
    "AIRWORTHINESS_CERT" => "Airworthiness Certificate", "INSURANCE" => "Insurance Policy",
    "RADIO" => "Radio Station License", "OTHER" => "Other"
  }.freeze
  # An expired registration means the aircraft may not be flown (14 CFR
  # 91.203(a)(2)); renewal takes a while, so warn earlier.
  GROUNDING_EXPIRY_TYPES = %w[REGISTRATION].freeze
  EXPIRY_WARNING_DAYS = { "REGISTRATION" => 90 }.freeze

  belongs_to :aircraft
  belongs_to :document_collection, optional: true
  has_many_attached :pages
  has_many :logbook_entries, dependent: :nullify

  validates :name, presence: true
  validates :doc_type, inclusion: { in: TYPES.keys }
  validates :visibility, inclusion: { in: DocumentCollection::VISIBILITIES.keys }, allow_nil: true
  validates_uploads :pages
  normalizes :visibility, with: ->(v) { v.presence }

  scope :ordered, -> { order(:name) }
  scope :expiring, -> { where.not(expires_on: nil) }

  def to_s = name
  def type_label = TYPES[doc_type]
  def expired?(today = Date.current) = expires_on.present? && today > expires_on

  # The page files the search text was read from; when they change, it's read again.
  def pages_source_key = pages.map(&:blob_id).sort.join(",")
  def pages_text_stale? = pages_text_source.to_s != pages_source_key

  after_commit(on: %i[create update]) { DocumentTextJob.perform_later(id) if pages.attached? && pages_text_stale? }
  def expiry_warning_days = EXPIRY_WARNING_DAYS.fetch(doc_type, 30)

  # nil visibility inherits from the collection; uncollected docs default to private.
  def effective_visibility
    visibility || document_collection&.visibility || "private"
  end

  def visible_to_share?(share)
    case effective_visibility
    when "status" then true
    when "maintenance" then share.maintenance?
    else false
    end
  end
end

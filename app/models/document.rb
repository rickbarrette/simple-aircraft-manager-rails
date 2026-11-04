class Document < ApplicationRecord
  include UploadValidation

  TYPES = {
    "LOG" => "Logbook", "ALTER" => "Alteration Record", "REPORT" => "Report",
    "ESTIMATE" => "Estimate", "DISC" => "Discrepancy List", "INVOICE" => "Receipt / Invoice",
    "AIRCRAFT" => "Aircraft Record", "OTHER" => "Other"
  }.freeze

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

  def to_s = name
  def type_label = TYPES[doc_type]

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

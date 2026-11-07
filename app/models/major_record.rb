class MajorRecord < ApplicationRecord
  RECORD_TYPES = { "repair" => "Major Repair", "alteration" => "Major Alteration" }.freeze

  belongs_to :aircraft
  belongs_to :component, optional: true
  belongs_to :form_337_document, class_name: "Document", optional: true
  belongs_to :stc_document, class_name: "Document", optional: true
  belongs_to :logbook_entry, optional: true
  # The recurring inspection this STC's Instructions for Continued
  # Airworthiness call for (owners must follow ICAs: 91.403(c), 43.13(a)).
  belongs_to :ica_inspection_type, class_name: "InspectionType", optional: true

  validates :title, :date_performed, presence: true
  validates :record_type, inclusion: { in: RECORD_TYPES.keys }

  scope :recent_first, -> { order(date_performed: :desc, created_at: :desc) }

  def type_label = RECORD_TYPES[record_type]
end

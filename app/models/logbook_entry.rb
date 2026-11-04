class LogbookEntry < ApplicationRecord
  LOG_TYPES = { "AC" => "Aircraft", "ENG" => "Engine", "PROP" => "Propeller", "OTHER" => "Other" }.freeze
  ENTRY_TYPES = {
    "MAINTENANCE" => "Maintenance", "INSPECTION" => "Inspection", "FLIGHT" => "Flight",
    "HOURS_UPDATE" => "Hours Update", "OTHER" => "Other"
  }.freeze

  belongs_to :aircraft
  belongs_to :document, optional: true
  has_many :inspection_records, dependent: :nullify
  has_many :ad_compliances, dependent: :nullify

  validates :date, :text, presence: true
  validates :log_type, inclusion: { in: LOG_TYPES.keys }
  validates :entry_type, inclusion: { in: ENTRY_TYPES.keys }

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def self.search(q)
    return all if q.blank?
    term = "%#{sanitize_sql_like(q)}%"
    where("text LIKE :t OR signoff_person LIKE :t OR signoff_location LIKE :t", t: term)
  end

  def to_s = "#{date} — #{LOG_TYPES[log_type]}"
end

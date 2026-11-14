class ConsumableRecord < ApplicationRecord
  TYPES = LabelSet.new("consumable_record.types", %w[oil fuel])
  UNITS = { "oil" => "qt", "fuel" => "gal" }.freeze

  belongs_to :aircraft
  belongs_to :flight_log, optional: true

  validates :record_type, inclusion: { in: TYPES.keys }
  validates :date, :flight_hours, presence: true
  validates :quantity_added, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :oil, -> { where(record_type: "oil") }
  scope :fuel, -> { where(record_type: "fuel") }
  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def unit = UNITS[record_type]
end

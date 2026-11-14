class InspectionType < ApplicationRecord
  # What it means for the aircraft when this inspection is overdue.
  EFFECTS = {
    "grounds" => "Grounds the aircraft",
    "no_ifr" => "No IFR flight (e.g. pitot-static, 91.411)",
    "no_transponder" => "Transponder can't be used (91.413)",
    "advisory" => "Advisory only"
  }.freeze
  # In a sentence: "Overdue: no IFR."
  EFFECT_SUMMARIES = { "grounds" => "grounds the aircraft", "no_ifr" => "no IFR", "no_transponder" => "transponder can't be used",
                       "advisory" => "advisory only" }.freeze
  # Short form for the airworthiness status ("VFR only").
  LIMITATIONS = { "no_ifr" => "VFR only", "no_transponder" => "No transponder" }.freeze

  include CalendarInterval
  calendar_interval :recurring, days: :recurring_days, months: :recurring_months, blank: 0
  include SharedRecordHistory # has_and_belongs_to_many :aircraft and :components, with history
  has_many :inspection_records, dependent: :destroy
  belongs_to :satisfies, class_name: "InspectionType", optional: true
  has_many :satisfied_by, class_name: "InspectionType", foreign_key: :satisfies_id, inverse_of: :satisfies, dependent: :nullify

  validates :name, presence: true
  validates :effect, inclusion: { in: EFFECTS.keys }
  validates :hours_tolerance, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate { errors.add(:satisfies, "can't be the inspection itself") if satisfies_id.present? && satisfies_id == id }
  # `required` mirrors effect, for archives shared with the original app.
  before_validation { self.required = effect != "advisory" }

  scope :ordered, -> { order(:name) }

  def to_s = name
  def limitation = LIMITATIONS[effect]
  def advisory? = effect == "advisory"

  # Records that count for this inspection on the aircraft: its own, plus
  # those of inspections that satisfy it (an annual for the 100-hour).
  def records_for(aircraft)
    InspectionRecord.for_aircraft(aircraft).where(inspection_type_id: [ id, *satisfied_by.ids ])
  end

  def due_rule
    { hours: recurring_hours.to_f, months: recurring_months, days: recurring_days } if recurring?
  end

  def interval_description
    return "One-time" unless recurring?
    parts = []
    parts << "#{recurring_hours.to_s.sub(/\.0\z/, '')} hrs" if recurring_hours.to_f > 0
    parts << recurring_interval_label if recurring_months > 0 && recurring_days.zero?
    parts << "#{recurring_months} months" if recurring_months > 0 && recurring_days > 0
    parts << "#{recurring_days} days" if recurring_days > 0
    parts.any? ? "Every #{parts.join(' / ')}" : "Recurring"
  end
end

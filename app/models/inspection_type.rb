class InspectionType < ApplicationRecord
  # What it means for the aircraft when this inspection is overdue.
  EFFECTS = LabelSet.new("inspection_type.effects", %w[grounds no_ifr no_transponder advisory])
  # In a sentence: "Overdue: no IFR."
  EFFECT_SUMMARIES = LabelSet.new("inspection_type.effect_summaries", %w[grounds no_ifr no_transponder advisory])
  # Short form for the airworthiness status ("VFR only").
  LIMITATIONS = LabelSet.new("inspection_type.limitations", %w[no_ifr no_transponder])

  include CalendarInterval
  calendar_interval :recurring, days: :recurring_days, months: :recurring_months, blank: 0
  include SharedRecordHistory # has_and_belongs_to_many :aircraft and :components, with history
  has_many :inspection_records, dependent: :destroy
  belongs_to :satisfies, class_name: "InspectionType", optional: true
  has_many :satisfied_by, class_name: "InspectionType", foreign_key: :satisfies_id, inverse_of: :satisfies, dependent: :nullify

  validates :name, presence: true
  validates :effect, inclusion: { in: EFFECTS.keys }
  validates :hours_tolerance, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate { errors.add(:satisfies, :itself) if satisfies_id.present? && satisfies_id == id }
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
    return I18n.t("models.inspection_type.one_time") unless recurring?
    parts = []
    parts << I18n.t("models.inspection_type.hours", hours: recurring_hours.to_s.sub(/\.0\z/, "")) if recurring_hours.to_f > 0
    parts << recurring_interval_label if recurring_months > 0 && recurring_days.zero?
    parts << CalendarInterval.label(0, recurring_months) if recurring_months > 0 && recurring_days > 0
    parts << CalendarInterval.label(recurring_days, 0) if recurring_days > 0
    parts.any? ? I18n.t("models.inspection_type.every", interval: parts.join(" / ")) : I18n.t("models.inspection_type.recurring")
  end
end

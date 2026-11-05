class InspectionType < ApplicationRecord
  has_and_belongs_to_many :aircraft
  has_and_belongs_to_many :components
  has_many :inspection_records, dependent: :destroy

  validates :name, presence: true

  scope :ordered, -> { order(:name) }

  # Applies to the aircraft directly, or to one of its components.
  def self.applicable_to(aircraft)
    direct = joins(:aircraft).where(aircraft: { id: aircraft.id }).select(:id)
    via_component = joins(:components).where(components: { aircraft_id: aircraft.id }).select(:id)
    where(id: direct).or(where(id: via_component))
  end

  def to_s = name

  def due_rule
    { hours: recurring_hours.to_f, months: recurring_months, days: recurring_days } if recurring?
  end

  def interval_description
    return "One-time" unless recurring?
    parts = []
    parts << "#{recurring_hours.to_s.sub(/\.0\z/, '')} hrs" if recurring_hours.to_f > 0
    parts << "#{recurring_months} months" if recurring_months > 0
    parts << "#{recurring_days} days" if recurring_days > 0
    parts.any? ? "Every #{parts.join(' / ')}" : "Recurring"
  end
end

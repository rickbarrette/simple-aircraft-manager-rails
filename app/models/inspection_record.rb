class InspectionRecord < ApplicationRecord
  include Versioned
  belongs_to :inspection_type
  belongs_to :aircraft, optional: true
  belongs_to :component, optional: true
  belongs_to :logbook_entry, optional: true
  has_many :ad_compliances, dependent: :nullify

  validates :date, presence: true
  validate { errors.add(:base, "Must belong to an aircraft or component") unless aircraft_id || component_id }

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  # Records belonging to the aircraft, or to any of its components.
  def self.for_aircraft(aircraft)
    where(aircraft_id: aircraft.id).or(where(component_id: aircraft.components.select(:id)))
  end

  # Hours at inspection, falling back to the linked logbook entry.
  def hours_at_inspection
    aircraft_hours || logbook_entry&.aircraft_hours_at_entry
  end
end

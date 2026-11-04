class AdCompliance < ApplicationRecord
  belongs_to :airworthiness_directive
  belongs_to :aircraft, optional: true
  belongs_to :component, optional: true
  belongs_to :logbook_entry, optional: true
  belongs_to :inspection_record, optional: true

  validates :date_complied, :compliance_notes, presence: true
  validate { errors.add(:base, "Must belong to an aircraft or component") unless aircraft_id || component_id }

  scope :recent_first, -> { order(date_complied: :desc, created_at: :desc) }

  def self.for_aircraft(aircraft)
    where(aircraft_id: aircraft.id).or(where(component_id: aircraft.components.select(:id)))
  end
end

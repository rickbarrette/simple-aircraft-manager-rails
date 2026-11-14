class AircraftEvent < ApplicationRecord
  CATEGORIES = LabelSet.new("aircraft_event.categories", %w[hours flight component squawk note oil fuel logbook ad inspection document aircraft role major_record oil_analysis])

  belongs_to :aircraft
  belongs_to :user, optional: true

  validates :category, inclusion: { in: CATEGORIES.keys }
  default_scope { order(created_at: :desc) }
end

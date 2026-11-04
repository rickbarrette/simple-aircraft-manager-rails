class AircraftEvent < ApplicationRecord
  CATEGORIES = {
    "hours" => "Hours Update", "flight" => "Flight", "component" => "Component",
    "squawk" => "Squawk", "note" => "Note", "oil" => "Oil", "fuel" => "Fuel",
    "logbook" => "Logbook", "ad" => "Airworthiness Directive", "inspection" => "Inspection",
    "document" => "Document", "aircraft" => "Aircraft", "role" => "Role",
    "major_record" => "Major Repair/Alteration"
  }.freeze

  belongs_to :aircraft
  belongs_to :user, optional: true

  validates :category, inclusion: { in: CATEGORIES.keys }
  default_scope { order(created_at: :desc) }
end

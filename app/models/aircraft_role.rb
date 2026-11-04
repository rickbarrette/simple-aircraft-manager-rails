class AircraftRole < ApplicationRecord
  ROLES = { "owner" => "Owner", "pilot" => "Pilot" }.freeze

  belongs_to :aircraft
  belongs_to :user

  validates :role, inclusion: { in: ROLES.keys }
  validates :user_id, uniqueness: { scope: :aircraft_id, message: "already has a role on this aircraft" }

  scope :owners, -> { where(role: "owner") }
end

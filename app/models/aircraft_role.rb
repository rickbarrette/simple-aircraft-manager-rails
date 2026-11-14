class AircraftRole < ApplicationRecord
  ROLES = LabelSet.new("aircraft_role.roles", %w[owner pilot])

  belongs_to :aircraft
  belongs_to :user

  validates :role, inclusion: { in: ROLES.keys }
  validates :user_id, uniqueness: { scope: :aircraft_id, message: "already has a role on this aircraft" }

  scope :owners, -> { where(role: "owner") }
end

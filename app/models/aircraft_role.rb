# Someone's role on an aircraft (Role), which decides what they can do there.
class AircraftRole < ApplicationRecord
  belongs_to :aircraft
  belongs_to :user
  belongs_to :role

  validates :user_id, uniqueness: { scope: :aircraft_id, message: "already has a role on this aircraft" }

  scope :owners, -> { joins(:role).where(roles: { key: "owner" }) }
  # Whose role includes a permission (Owner always does).
  scope :with_permission, ->(permission) {
    joins(:role).where("roles.key = 'owner' OR EXISTS (SELECT 1 FROM json_each(roles.permissions) WHERE json_each.value = ?)", permission.to_s)
  }

  # A Role, or a built-in role's key ("owner", "pilot").
  def role=(value)
    super(value.is_a?(Role) || value.nil? ? value : Role.for_key(value))
  end

  def owner? = role&.owner?
end

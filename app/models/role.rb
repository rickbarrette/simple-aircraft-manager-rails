# A role someone can have on an aircraft: a name and a set of permissions
# (Permission). Installation-wide; administrators manage them (Admin → Roles).
# Four are built in (key set): Owner, which always has every permission so an
# aircraft can always be managed, and Mechanic, Pilot and Viewer, whose
# permissions can be changed. Administrators can add their own.
class Role < ApplicationRecord
  BUILT_IN = %w[owner mechanic pilot viewer].freeze

  has_many :aircraft_roles, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.squish }
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 40 }
  validates :description, length: { maximum: 200 }
  validates :key, inclusion: { in: BUILT_IN }, uniqueness: true, allow_nil: true
  before_validation { self.permissions = Array(permissions).map(&:to_s) & Permission::ALL }
  before_destroy { throw :abort if built_in? }

  scope :ordered, -> { order(Arel.sql("CASE WHEN key IS NULL THEN 1 ELSE 0 END"), :position, :name) }

  # The built-in roles, created when first needed (a new installation, tests).
  def self.ensure_built_in!
    BUILT_IN.each_with_index do |key, i|
      find_or_create_by!(key: key) do |role|
        role.name = I18n.t("roles.#{key}.name")
        role.description = I18n.t("roles.#{key}.description")
        role.permissions = Permission::DEFAULTS.fetch(key, [])
        role.position = i
      end
    end
  end

  def self.for_key(key) = find_by(key: key.to_s) || (ensure_built_in! && find_by!(key: key.to_s))
  def self.owner = for_key("owner")

  def built_in? = key.present?
  def owner? = key == "owner"

  def permissions = owner? ? Permission::ALL : super
  def can?(permission) = permissions.include?(permission.to_s)
end

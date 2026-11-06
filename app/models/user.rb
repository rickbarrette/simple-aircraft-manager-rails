class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :aircraft_roles, dependent: :destroy
  has_many :aircraft, through: :aircraft_roles
  has_one :air_trail_connection, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Aircraft visible to this user: admins see the whole fleet.
  def accessible_aircraft
    admin? ? Aircraft.all : aircraft
  end

  # 'admin' | 'owner' | 'pilot' | nil
  def role_for(aircraft)
    return "admin" if admin?
    aircraft_roles.find_by(aircraft: aircraft)&.role
  end

  def display_name
    name.presence || email_address
  end
end

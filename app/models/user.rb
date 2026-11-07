class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :aircraft_roles, dependent: :destroy
  has_many :aircraft, through: :aircraft_roles
  has_one :air_trail_connection, dependent: :destroy
  has_many :certificates, -> { ordered }, class_name: "UserCertificate", dependent: :destroy
  has_many :entry_signatures, dependent: :nullify

  scope :active, -> { where(disabled_at: nil) }

  def disabled? = disabled_at.present?

  # Emailed sign-in links: valid 15 minutes, and spent by the next sign-in of
  # any kind (or an email change), so each link works once. last_signed_in_at
  # only moves forward; signing out can't bring a used link back.
  generates_token_for :email_sign_in, expires_in: 15.minutes do
    [ email_address, last_signed_in_at&.to_f ]
  end

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

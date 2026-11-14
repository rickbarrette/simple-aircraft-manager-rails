class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :aircraft_roles, dependent: :destroy
  has_many :push_subscriptions, dependent: :delete_all
  has_many :aircraft, through: :aircraft_roles
  has_one :air_trail_connection, dependent: :destroy
  has_many :certificates, -> { ordered }, class_name: "UserCertificate", dependent: :destroy
  has_many :entry_signatures, dependent: :nullify
  has_secure_token :calendar_token, length: 32

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
  PASSWORD_MIN = 12
  validates :password, length: { minimum: PASSWORD_MIN, maximum: 72 }, allow_nil: true
  validate :password_not_breached

  # Lockout: this many failed sign-ins in a row (password, authenticator
  # code, or password at signing) locks the account for a while, from
  # whatever address they come. The user is emailed.
  LOCK_AFTER = 10
  LOCK_FOR = 15.minutes

  encrypts :otp_secret
  OTP_ISSUER = "Simple Aircraft Manager".freeze
  RECOVERY_CODES = 10

  # Password sign-in with lockout. Returns the user, or nil (wrong details,
  # or locked: the same answer, so it doesn't reveal which).
  def self.authenticate_with_lockout(email_address:, password:)
    user = find_by(email_address: email_address.to_s.strip.downcase)
    return if user&.locked?
    authed = authenticate_by(email_address: email_address.to_s, password: password.to_s)
    authed ? authed.tap(&:clear_failed_sign_ins!) : user&.register_failed_sign_in!
  end

  def locked? = locked_until&.future?

  # Counts a failed attempt; locks the account (and returns nil) at the limit.
  def register_failed_sign_in!
    self.class.where(id: id).update_all("failed_sign_ins = failed_sign_ins + 1")
    reload
    if failed_sign_ins >= LOCK_AFTER
      update_columns(failed_sign_ins: 0, locked_until: LOCK_FOR.from_now)
      SessionsMailer.locked(self).deliver_later if MailSettings.configured?
      Rails.logger.warn("[auth] #{email_address} locked after #{LOCK_AFTER} failed sign-ins")
    end
    nil
  end

  def clear_failed_sign_ins!
    update_columns(failed_sign_ins: 0, locked_until: nil) if failed_sign_ins.positive? || locked_until
  end

  def unlock! = update_columns(failed_sign_ins: 0, locked_until: nil)

  # --- Authenticator app (TOTP) ---

  def otp_enabled? = otp_enabled_at.present? && otp_secret.present?

  def self.new_otp_secret = ROTP::Base32.random

  def self.otp_uri(secret, email) = ROTP::TOTP.new(secret, issuer: OTP_ISSUER).provisioning_uri(email)

  # A code from the authenticator for this secret, allowing 30 s of clock drift.
  def self.valid_otp?(secret, code, after: nil)
    ROTP::TOTP.new(secret, issuer: OTP_ISSUER).verify(code.to_s.gsub(/\s/, ""), drift_behind: 30, drift_ahead: 30, after: after)
  end

  # Turns it on with a confirmed secret; returns the recovery codes to show once.
  def enable_otp!(secret)
    codes = Array.new(RECOVERY_CODES) { SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-") }
    update!(otp_secret: secret, otp_enabled_at: Time.current, otp_last_used_at: nil, otp_recovery_codes: codes.map { recovery_digest(_1) })
    codes
  end

  def disable_otp! = update!(otp_secret: nil, otp_enabled_at: nil, otp_last_used_at: nil, otp_recovery_codes: nil)

  # An authenticator code (each accepted once) or an unused recovery code.
  def verify_second_factor(code)
    return false unless otp_enabled?
    code = code.to_s.strip.downcase
    if code.gsub(/\s/, "").match?(/\A\d{6}\z/)
      step = self.class.valid_otp?(otp_secret, code, after: otp_last_used_at)
      step ? update_columns(otp_last_used_at: step) && true : false
    else
      digests = Array(otp_recovery_codes)
      match = digests.find { ActiveSupport::SecurityUtils.secure_compare(_1, recovery_digest(code)) }
      match ? update_columns(otp_recovery_codes: digests - [ match ]) && true : false
    end
  end

  def recovery_codes_left = Array(otp_recovery_codes).size

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

  private

  def recovery_digest(code) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("otp-recovery", 32), code.to_s.strip.downcase)

  def password_not_breached
    return if password.blank? || errors.include?(:password)
    errors.add(:password, :breached) if PwnedPasswords.breached?(password)
  end
end

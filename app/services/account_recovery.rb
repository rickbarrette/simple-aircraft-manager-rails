# Account recovery from the server's command line (lib/tasks/users.rake),
# for when nobody can sign in to fix things in the app: a forgotten admin
# password, a lockout, a lost authenticator, a disabled or demoted admin.
# Whoever can run commands on the server already controls the data, so
# these need no other proof. Every action is logged.
class AccountRecovery
  class Error < StandardError; end

  def self.find!(email)
    User.find_by(email_address: email.to_s.strip.downcase) or raise Error, "No account with the email #{email.inspect}. List them with: bin/rails users:list"
  end

  def self.list
    User.order(:email_address).map do |u|
      flags = [ ("admin" if u.admin?), ("DISABLED" if u.disabled?), ("LOCKED" if u.locked?), ("2FA" if u.otp_enabled?), ("SSO" if u.sso_uid?) ].compact
      "#{u.email_address.ljust(36)} #{u.name.to_s.truncate(24).ljust(24)} #{flags.join(' ').ljust(26)} last sign-in: #{u.last_signed_in_at&.to_date || 'never'}"
    end
  end

  # Sets a new password (the one given, or a generated one, returned so it can
  # be shown once), unlocks the account and signs out its sessions.
  def self.reset_password!(email, password: nil)
    user = find!(email)
    password = password.presence || generate_password
    user.password = user.password_confirmation = password
    raise Error, "Password not accepted: #{user.errors.full_messages.to_sentence}" unless user.save
    user.unlock!
    user.sessions.destroy_all
    log(user, "password reset")
    password
  end

  # A one-time sign-in link (15 minutes), as the "Email me a sign-in link"
  # email would contain, for when email isn't working.
  def self.sign_in_link(email)
    user = find!(email)
    raise Error, "That account is disabled: enable it first (bin/rails \"users:enable[#{user.email_address}]\")" if user.disabled?
    raise Error, "Password sign-in is turned off (PASSWORD_LOGIN=false), so sign-in links don't work: unset it and restart, or fix single sign-on" unless Sso.password_login?
    log(user, "sign-in link made")
    "#{Sso.app_url}#{Rails.application.routes.url_helpers.sign_in_link_path(user.generate_token_for(:email_sign_in))}"
  end

  def self.unlock!(email) = find!(email).tap { _1.unlock!; log(_1, "unlocked") }
  def self.reset_two_factor!(email) = find!(email).tap { _1.disable_otp!; log(_1, "two-factor turned off") }

  def self.enable!(email) = find!(email).tap { _1.update!(disabled_at: nil); log(_1, "enabled") }

  def self.disable!(email)
    find!(email).tap do |user|
      user.update!(disabled_at: Time.current)
      user.sessions.destroy_all
      log(user, "disabled")
    end
  end

  def self.make_admin!(email) = find!(email).tap { _1.update!(admin: true); log(_1, "made an admin") }

  # A new admin account, for when there's none left to sign in with.
  def self.create_admin!(email, name: nil, password: nil)
    raise Error, "#{email} already has an account: use users:reset_password and users:make_admin" if User.exists?(email_address: email.to_s.strip.downcase)
    password = password.presence || generate_password
    user = User.new(email_address: email, name: name.presence, password: password, password_confirmation: password, admin: true)
    raise Error, "Account not created: #{user.errors.full_messages.to_sentence}" unless user.save
    log(user, "admin account created")
    [ user, password ]
  end

  # Ends every session of every user (suspected compromise): everyone signs
  # in again, through the lockout and two-factor checks.
  def self.sign_out_all!
    count = Session.delete_all
    Rails.logger.warn("[account recovery] all #{count} sessions ended from the command line")
    count
  end

  def self.generate_password = SecureRandom.alphanumeric(20).scan(/.{5}/).join("-")

  def self.log(user, what) = Rails.logger.warn("[account recovery] #{user.email_address}: #{what} from the command line")
end

# Finishes an OpenID Connect sign-in (OmniAuth runs the redirect dance) and
# links or unlinks a signed-in user's account. See Sso for the settings.
#
# Accounts are matched by the provider's stable subject id. The first time,
# an existing account is linked by email only when the provider says the
# email is verified (or OIDC_TRUST_EMAIL is on), since some providers let
# users edit their email. Otherwise, sign in with a password once and link
# from the profile page.
class SsoController < ApplicationController
  allow_unauthenticated_access only: %i[callback failure]
  before_action :require_sso
  rate_limit to: 20, within: 3.minutes, only: :callback, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def callback
    auth = request.env["omniauth.auth"]
    return failure unless auth && auth.provider.to_s == Sso::PROVIDER.to_s && auth.uid.present?
    return reauthenticated(auth) if authenticated? && current_user.sso_uid.present? && current_user.sso_uid == auth.uid.to_s
    return link(auth) if authenticated?

    user = User.find_by(sso_uid: auth.uid) || link_by_email(auth) || create_user(auth)
    unless user
      email = auth.info&.email.presence
      return redirect_to new_session_path, alert: "There's no account for #{email || 'that sign-in'} here yet. " \
                                                  "Ask an administrator to add you, or sign in with your password and link #{Sso.label} from your profile."
    end

    return redirect_to new_session_path, alert: "This account is disabled." if user.disabled?

    sync_admin(user, auth)
    return_to = session[:return_to_after_authenticating]
    reset_session # fresh session id after signing in
    start_new_session_for user
    redirect_to return_to || root_url
  end

  # OmniAuth's error codes; anything else (network errors…) is logged, not shown.
  FAILURES = { "invalid_credentials" => "invalid credentials", "csrf_detected" => "the sign-in expired, try again",
               "access_denied" => "access denied", "timeout" => "timed out" }.freeze

  def failure
    reason = FAILURES[params[:message].to_s]
    Rails.logger.warn("[sso] sign-in failed: #{params[:message].to_s.truncate(300)}") unless reason
    redirect_to(authenticated? ? edit_profile_path : new_session_path,
                alert: "#{Sso.label} sign-in failed (#{reason || "couldn't reach or verify #{Sso.label}; see the server log"}).")
  end

  def destroy
    unless Sso.password_login?
      return redirect_to edit_profile_path, alert: "Password sign-in is off, so unlinking #{Sso.label} would lock you out."
    end
    current_user.update!(sso_uid: nil)
    redirect_to edit_profile_path, notice: "#{Sso.label} unlinked. Sign in with your email and password from now on."
  end

  private

  def require_sso
    raise ActiveRecord::RecordNotFound unless Sso.enabled?
  end

  # Signed in again (e.g. to sign a logbook entry): note when, and go back.
  def reauthenticated(auth)
    session[:reauthenticated_at] = Time.current.to_i
    redirect_to session.delete(:after_reauth).presence || edit_profile_path, notice: "Signed in again with #{Sso.label}."
  end

  def link(auth)
    owner = User.find_by(sso_uid: auth.uid)
    if owner && owner != current_user
      redirect_to edit_profile_path, alert: "That #{Sso.label} account is already linked to another user."
    else
      current_user.update!(sso_uid: auth.uid)
      redirect_to edit_profile_path, notice: "#{Sso.label} linked. You can now sign in with it."
    end
  end

  def link_by_email(auth)
    email = auth.info&.email.to_s.strip.downcase
    return if email.blank? || !(email_verified?(auth) || Sso.trust_email?)
    user = User.find_by(email_address: email, sso_uid: nil)
    user&.update!(sso_uid: auth.uid)
    user
  end

  def create_user(auth)
    return unless Sso.auto_create_users?
    email = auth.info&.email.to_s.strip.downcase
    return if email.blank? || User.exists?(email_address: email)
    # The random password is never shown; a password reset can set a real one.
    User.create!(email_address: email, name: auth.info&.name.presence, sso_uid: auth.uid, password: SecureRandom.base58(40))
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def email_verified?(auth)
    [ true, "true" ].include?(raw_info(auth)["email_verified"])
  end

  # With OIDC_ADMIN_GROUP set, the provider decides who's an admin. Skipped
  # when the token carries no groups claim, so a missing scope can't demote.
  def sync_admin(user, auth)
    return unless Sso.admin_group && raw_info(auth).key?("groups")
    user.update!(admin: Array(raw_info(auth)["groups"]).map(&:to_s).include?(Sso.admin_group))
  end

  def raw_info(auth)
    (auth.extra&.raw_info || {}).to_h.stringify_keys
  end
end

# Finishes an OpenID Connect sign-in (OmniAuth runs the redirect dance) and
# links or unlinks a signed-in user's account. See Sso for the settings.
#
# Accounts are matched by the provider's stable subject id. The first time,
# an existing account is linked by email only when the provider says the
# email is verified (or OIDC_TRUST_EMAIL is on), since some providers let
# users edit their email. Otherwise, sign in with a password once and link
# from the profile page.
#
# Someone without an account gets one only from an invitation they opened
# first that can make one (an administrator's AccessInvitation, accepted at
# once; an Owner's SigningInvitation, for its address), or for anyone the
# provider lets in when OIDC_AUTO_CREATE_USERS is on.
class SsoController < ApplicationController
  allow_unauthenticated_access only: %i[callback failure]
  before_action :require_sso
  rate_limit to: 20, within: 3.minutes, only: :callback, with: -> { redirect_to new_session_path, alert: t("flash.sso.try_again_later") }

  def callback
    auth = request.env["omniauth.auth"]
    return failure unless auth && auth.provider.to_s == Sso::PROVIDER.to_s && auth.uid.present?
    return reauthenticated(auth) if authenticated? && current_user.sso_uid.present? && current_user.sso_uid == auth.uid.to_s
    return link(auth) if authenticated?

    user = User.find_by(sso_uid: auth.uid) || link_by_email(auth) || create_user(auth)
    unless user
      email = auth.info&.email.presence
      return redirect_to new_session_path, alert: t("flash.sso.there_s_no_account", email: email || t("flash.sso.that_sign_in"), provider: Sso.label)
    end

    return redirect_to new_session_path, alert: t("flash.sso.this_account_is_disabled") if user.disabled?

    sync_admin(user, auth)
    return_to = session[:return_to_after_authenticating]
    reset_session # fresh session id after signing in
    start_new_session_for user
    return redirect_to(root_url, notice: [ t("flash.joins.welcome"), AccessInvitation.describe(@joined) ].join(" ").strip) if @joined
    redirect_to return_to || root_url
  end

  # OmniAuth's error codes; anything else (network errors…) is logged, not shown.
  FAILURES = %w[invalid_credentials csrf_detected access_denied timeout].freeze

  def failure
    reason = t(params[:message], scope: "flash.sso.failures") if FAILURES.include?(params[:message].to_s)
    Rails.logger.warn("[sso] sign-in failed: #{params[:message].to_s.truncate(300)}") unless reason
    redirect_to(authenticated? ? edit_profile_path : new_session_path,
                alert: t("flash.sso.failed", provider: Sso.label, reason: reason || t("flash.sso.unreachable", provider: Sso.label)))
  end

  def destroy
    unless Sso.password_login?
      return redirect_to edit_profile_path, alert: t("flash.sso.password_sign_in_is", label: Sso.label)
    end
    current_user.update!(sso_uid: nil)
    redirect_to edit_profile_path, notice: t("flash.sso.unlinked_sign_in_with", label: Sso.label)
  end

  private

  def require_sso
    raise ActiveRecord::RecordNotFound unless Sso.enabled?
  end

  # Signed in again (e.g. to sign a logbook entry): note when, and go back.
  def reauthenticated(auth)
    session[:reauthenticated_at] = Time.current.to_i
    redirect_to session.delete(:after_reauth).presence || edit_profile_path, notice: t("flash.sso.signed_in_again_with", label: Sso.label)
  end

  def link(auth)
    owner = User.find_by(sso_uid: auth.uid)
    if owner && owner != current_user
      redirect_to edit_profile_path, alert: t("flash.sso.that_account_is_already", label: Sso.label)
    else
      current_user.update!(sso_uid: auth.uid)
      redirect_to edit_profile_path, notice: t("flash.sso.linked_you_can_now", label: Sso.label)
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
    email = auth.info&.email.to_s.strip.downcase
    return if email.blank? || User.exists?(email_address: email)
    invitation = invitation_making_account(email)
    return unless invitation || signing_invitation_making_account?(email) || Sso.auto_create_users?
    User.transaction do
      # The random password is never shown; a password reset can set a real one.
      user = User.create!(email_address: email, name: auth.info&.name.presence, sso_uid: auth.uid, password: SecureRandom.base58(40))
      @joined = invitation&.redeem!(user)
      user
    end
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # A signing invitation opened in this browser before signing in, from an
  # Owner, for this email address.
  def signing_invitation_making_account?(email)
    invitation = SigningInvitation.find_usable(session[:signing_token])
    invitation.present? && invitation.creates_account? && invitation.email == email
  end

  # The invitation opened in this browser before signing in, when it can
  # make an account (an administrator's) for this email address.
  def invitation_making_account(email)
    invitation = AccessInvitation.find_by_token(session[:join_token])
    invitation if invitation&.usable? && invitation.creates_accounts? && invitation.for_email?(email)
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

# Sign in with a link sent by email instead of a password.
#
# Opening the link shows a confirm button rather than signing in straight
# away: mail scanners that pre-open links would otherwise use up the one-time
# link (and sign themselves in).
class SignInLinksController < ApplicationController
  allow_unauthenticated_access
  before_action :require_email_sign_in
  before_action :set_user_by_token, only: %i[show consume]
  rate_limit to: 5, within: 15.minutes, only: :create, with: -> { redirect_to new_sign_in_link_path, alert: t("flash.sign_in_links.try_again_later") }
  rate_limit to: 20, within: 15.minutes, only: :consume, with: -> { redirect_to new_session_path, alert: t("flash.sign_in_links.try_again_later_2") }

  def new
  end

  def create
    if (user = User.active.find_by(email_address: params[:email_address].to_s))
      SessionsMailer.sign_in_link(user).deliver_later
    end
    # Same answer either way, so this can't be used to find accounts.
    redirect_to new_session_path, notice: t("flash.sign_in_links.if_there_s_an")
  end

  def show
  end

  def consume
    return redirect_to new_session_path, alert: t("flash.sign_in_links.this_account_is_disabled") if @user.disabled?
    begin_sign_in @user, return_to: root_path, notice: t("flash.sign_in_links.signed_in") # signing in also spends the link
  end

  private

  def require_email_sign_in
    redirect_to new_session_path, alert: t("flash.sign_in_links.sign_in_with", label: Sso.label) unless Sso.password_login?
  end

  def set_user_by_token
    @user = User.find_by_token_for(:email_sign_in, params[:token].to_s)
    redirect_to new_sign_in_link_path, alert: t("flash.sign_in_links.that_sign_in_link") unless @user
  end
end

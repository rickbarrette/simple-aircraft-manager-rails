# Sign in with a link sent by email instead of a password.
#
# Opening the link shows a confirm button rather than signing in straight
# away: mail scanners that pre-open links would otherwise use up the one-time
# link (and sign themselves in).
class SignInLinksController < ApplicationController
  allow_unauthenticated_access
  before_action :require_email_sign_in
  before_action :set_user_by_token, only: %i[show consume]
  rate_limit to: 5, within: 15.minutes, only: :create, with: -> { redirect_to new_sign_in_link_path, alert: "Try again later." }
  rate_limit to: 20, within: 15.minutes, only: :consume, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if (user = User.active.find_by(email_address: params[:email_address].to_s))
      SessionsMailer.sign_in_link(user).deliver_later
    end
    # Same answer either way, so this can't be used to find accounts.
    redirect_to new_session_path, notice: "If there's an account for that address, a sign-in link is on its way. It works once, for 15 minutes."
  end

  def show
  end

  def consume
    return redirect_to new_session_path, alert: "This account is disabled." if @user.disabled?
    begin_sign_in @user, return_to: root_path, notice: "Signed in." # signing in also spends the link
  end

  private

  def require_email_sign_in
    redirect_to new_session_path, alert: "Sign in with #{Sso.label}." unless Sso.password_login?
  end

  def set_user_by_token
    @user = User.find_by_token_for(:email_sign_in, params[:token].to_s)
    redirect_to new_sign_in_link_path, alert: "That sign-in link has expired or was already used. Get a new one below." unless @user
  end
end

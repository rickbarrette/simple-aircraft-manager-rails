class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_url, alert: "Try again later." }

  def new
  end

  def create
    return redirect_to new_session_path, alert: "Sign in with #{Sso.label}." unless Sso.password_login?

    if user = User.authenticate_by(params.permit(:email_address, :password))
      return_to = after_authentication_url
      reset_session # fresh session id after signing in
      start_new_session_for user
      redirect_to return_to
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end
end

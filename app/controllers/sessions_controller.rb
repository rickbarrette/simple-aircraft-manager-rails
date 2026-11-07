class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create two_factor verify_two_factor]
  rate_limit to: 10, within: 3.minutes, only: %i[create verify_two_factor], with: -> { redirect_to new_session_url, alert: "Try again later." }

  FAILED = "Try another email address or password. After #{User::LOCK_AFTER} failed tries in a row an account is locked for #{User::LOCK_FOR.inspect}.".freeze

  def new
  end

  def create
    return redirect_to new_session_path, alert: "Sign in with #{Sso.label}." unless Sso.password_login?

    if (user = User.authenticate_with_lockout(email_address: params[:email_address], password: params[:password])) && user.disabled?
      redirect_to new_session_path, alert: "This account is disabled."
    elsif user
      begin_sign_in user, return_to: after_authentication_url
    else
      redirect_to new_session_path(email_address: params[:email_address].to_s.first(200)), alert: FAILED
    end
  end

  # Second step for accounts with an authenticator app.
  def two_factor
    redirect_to new_session_path, alert: "Sign in again." unless pending_otp_user
  end

  def verify_two_factor
    user = pending_otp_user
    return redirect_to(new_session_path, alert: "That took too long. Sign in again.") unless user
    if user.locked?
      reset_session
      redirect_to new_session_path, alert: FAILED
    elsif user.verify_second_factor(params[:code])
      user.clear_failed_sign_ins!
      return_to = after_authentication_url
      reset_session
      start_new_session_for user
      notice = user.recovery_codes_left < 3 ? "Signed in. You have #{user.recovery_codes_left} recovery codes left: make new ones on your profile." : nil
      redirect_to return_to, notice: notice
    else
      user.register_failed_sign_in!
      redirect_to two_factor_session_path, alert: "That code didn't match. Try the current code from your authenticator app, or a recovery code."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end
end

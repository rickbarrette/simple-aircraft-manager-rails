class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create two_factor verify_two_factor]
  rate_limit to: 10, within: 3.minutes, only: %i[create verify_two_factor], with: -> { redirect_to new_session_url, alert: t("flash.sessions.try_again_later") }


  def new
  end

  def create
    return redirect_to new_session_path, alert: t("flash.sessions.sign_in_with", label: Sso.label) unless Sso.password_login?

    if (user = User.authenticate_with_lockout(email_address: params[:email_address], password: params[:password])) && user.disabled?
      redirect_to new_session_path, alert: t("flash.sessions.this_account_is_disabled")
    elsif user
      begin_sign_in user, return_to: after_authentication_url
    else
      redirect_to new_session_path(email_address: params[:email_address].to_s.first(200)), alert: t("flash.sessions.failed", tries: User::LOCK_AFTER, minutes: User::LOCK_FOR.in_minutes.to_i)
    end
  end

  # Second step for accounts with an authenticator app.
  def two_factor
    redirect_to new_session_path, alert: t("flash.sessions.sign_in_again") unless pending_otp_user
  end

  def verify_two_factor
    user = pending_otp_user
    return redirect_to(new_session_path, alert: t("flash.sessions.that_took_too_long")) unless user
    if user.locked?
      reset_session
      redirect_to new_session_path, alert: t("flash.sessions.failed", tries: User::LOCK_AFTER, minutes: User::LOCK_FOR.in_minutes.to_i)
    elsif user.verify_second_factor(params[:code])
      user.clear_failed_sign_ins!
      return_to = after_authentication_url
      reset_session
      start_new_session_for user
      notice = user.recovery_codes_left < 3 ? t("flash.sessions.few_recovery_codes", count: user.recovery_codes_left) : nil
      redirect_to return_to, notice: notice
    else
      user.register_failed_sign_in!
      redirect_to two_factor_session_path, alert: t("flash.sessions.that_code_didn_t")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end
end

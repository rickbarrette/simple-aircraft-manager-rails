class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_password_login
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 5, within: 15.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  rate_limit to: 10, within: 15.minutes, only: :update, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    if params[:password].present? && @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all # a reset signs out every device
      redirect_to new_session_path, notice: "Password has been reset."
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence.presence || "Enter a new password."
    end
  end

  private
    def require_password_login
      redirect_to new_session_path, alert: "Sign in with #{Sso.label}." unless Sso.password_login?
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: "Password reset link is invalid or has expired."
    end
end

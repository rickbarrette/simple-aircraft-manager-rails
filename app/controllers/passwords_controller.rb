class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_password_login
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 5, within: 15.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("flash.passwords.try_again_later") }
  rate_limit to: 10, within: 15.minutes, only: :update, with: -> { redirect_to new_session_path, alert: t("flash.passwords.try_again_later_2") }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: t("flash.passwords.password_reset_instructions_sent")
  end

  def edit
  end

  def update
    if params[:password].present? && @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all # a reset signs out every device
      redirect_to new_session_path, notice: t("flash.passwords.password_has_been_reset")
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence.presence || "Enter a new password."
    end
  end

  private
    def require_password_login
      redirect_to new_session_path, alert: t("flash.passwords.sign_in_with", label: Sso.label) unless Sso.password_login?
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("flash.passwords.password_reset_link_is")
    end
end

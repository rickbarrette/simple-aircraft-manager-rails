class Admin::UsersController < ApplicationController
  before_action :require_admin!
  before_action :set_user, only: %i[edit update destroy disable enable unlock reset_two_factor]

  def index
    @users = User.order(:email_address).includes(:certificates, aircraft_roles: :aircraft)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.admin = admin_flag
    if @user.save
      redirect_to admin_users_path, notice: t("flash.admin_users.user_created", email_address: @user.email_address)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user == current_user && !admin_flag
      return redirect_to admin_users_path, alert: t("flash.admin_users.you_can_t_remove")
    end
    @user.admin = admin_flag
    if @user.update(attrs)
      @user.sessions.where.not(id: Current.session.id).destroy_all if attrs.key?(:password) # new password signs them out
      redirect_to admin_users_path, notice: t("flash.admin_users.user_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Ends their access and their ability to sign (AC 120-78B 2.2.6.4) while
  # keeping their account, so the signatures they made stay attributed.
  def unlock
    @user.unlock!
    redirect_to admin_users_path, notice: t("flash.admin_users.unlocked", email_address: @user.email_address)
  end

  # For a user who lost their authenticator: they sign in with their password
  # alone and can set it up again.
  def reset_two_factor
    @user.disable_otp!
    Rails.logger.info("[auth] #{current_user.email_address} turned off two-factor for #{@user.email_address}")
    redirect_to admin_users_path, notice: t("flash.admin_users.two_factor_turned_off", email_address: @user.email_address)
  end

  def disable
    return redirect_to admin_users_path, alert: t("flash.admin_users.you_can_t_disable") if @user == current_user
    @user.update!(disabled_at: Time.current)
    @user.sessions.destroy_all
    redirect_to admin_users_path, notice: t("flash.admin_users.disabled_signed_out_can", email_address: @user.email_address)
  end

  def enable
    @user.update!(disabled_at: nil)
    redirect_to admin_users_path, notice: t("flash.admin_users.enabled", email_address: @user.email_address)
  end

  def destroy
    return redirect_to admin_users_path, alert: t("flash.admin_users.you_can_t_delete") if @user == current_user
    if @user.entry_signatures.exists?
      return redirect_to admin_users_path, alert: t("flash.admin_users.has_signed_logbook_entries", email_address: @user.email_address)
    end
    @user.destroy!
    redirect_to admin_users_path, notice: t("flash.admin_users.user_deleted")
  end

  private

  def set_user = @user = User.find(params[:id])
  def user_params = params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  def admin_flag = params.dig(:user, :admin) == "1"
end

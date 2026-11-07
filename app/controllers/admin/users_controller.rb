class Admin::UsersController < ApplicationController
  before_action :require_admin!
  before_action :set_user, only: %i[edit update destroy]

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
      redirect_to admin_users_path, notice: "User #{@user.email_address} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user == current_user && !admin_flag
      return redirect_to admin_users_path, alert: "You can't remove your own admin rights."
    end
    @user.admin = admin_flag
    if @user.update(attrs)
      @user.sessions.where.not(id: Current.session.id).destroy_all if attrs.key?(:password) # new password signs them out
      redirect_to admin_users_path, notice: "User updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    return redirect_to admin_users_path, alert: "You can't delete yourself." if @user == current_user
    @user.destroy!
    redirect_to admin_users_path, notice: "User deleted."
  end

  private

  def set_user = @user = User.find(params[:id])
  def user_params = params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
  def admin_flag = params.dig(:user, :admin) == "1"
end

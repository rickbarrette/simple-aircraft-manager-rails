class SetupController < ApplicationController
  allow_unauthenticated_access
  before_action { redirect_to root_path if User.exists? }
  layout "public"

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.require(:user).permit(:name, :email_address, :password, :password_confirmation))
    @user.admin = true
    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome! You're the administrator. Add your first aircraft."
    else
      render :new, status: :unprocessable_entity
    end
  end
end

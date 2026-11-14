class SetupController < ApplicationController
  allow_unauthenticated_access
  before_action { redirect_to root_path if User.exists? }
  rate_limit to: 10, within: 15.minutes, only: :create, with: -> { redirect_to new_setup_path, alert: t("flash.setup.try_again_later") }
  layout "public"

  def new
    @user = User.new
    SetupCode.announce
  end

  def create
    @user = User.new(params.require(:user).permit(:name, :email_address, :password, :password_confirmation))
    @user.admin = true
    unless SetupCode.matches?(params[:setup_code])
      @user.errors.add(:base, t("flash.setup.wrong_code"))
      SetupCode.announce
      return render(:new, status: :unprocessable_entity)
    end
    if @user.save
      SetupCode.clear
      start_new_session_for @user
      redirect_to root_path, notice: t("flash.setup.welcome_you_re_the")
    else
      render :new, status: :unprocessable_entity
    end
  end
end

class ProfilesController < ApplicationController
  def edit
    @user = current_user
  end

  def update
    @user = current_user
    attrs = params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user.update(attrs)
      redirect_to root_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end

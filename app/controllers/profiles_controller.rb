class ProfilesController < ApplicationController
  def edit
    @user = current_user
  end

  # Changing the email or password needs the current password, so a session
  # left open somewhere can't be turned into a takeover of the account.
  def update
    @user = current_user
    attrs = params.require(:user).permit(:name, :email_address, :password, :password_confirmation, :reminder_emails)
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    new_email = User.normalize_value_for(:email_address, attrs[:email_address].to_s) if attrs.key?(:email_address)
    sensitive = (new_email && new_email != @user.email_address) || attrs.key?(:password)
    # Checked before assigning: setting a new password replaces the digest at once.
    if sensitive && !@user.authenticate_password(params.dig(:user, :current_password).to_s)
      @user.assign_attributes(attrs.except(:password, :password_confirmation))
      @user.errors.add(:base, "Enter your current password to change your email or password")
      return render :edit, status: :unprocessable_entity
    end
    @user.assign_attributes(attrs)
    if @user.save
      @user.sessions.where.not(id: Current.session.id).destroy_all if attrs.key?(:password)
      redirect_to root_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def sign_out_others
    count = current_user.sessions.where.not(id: Current.session.id).destroy_all.size
    redirect_to edit_profile_path, notice: "Signed out #{helpers.pluralize(count, 'other session')}."
  end
end

class SessionsMailer < ApplicationMailer
  def sign_in_link(user)
    @user = user
    @token = user.generate_token_for(:email_sign_in)
    mail subject: t(".subject"), to: user.email_address
  end

  def locked(user)
    @user = user
    mail subject: t(".subject"), to: user.email_address
  end
end

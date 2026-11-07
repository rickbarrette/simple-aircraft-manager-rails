class SessionsMailer < ApplicationMailer
  def sign_in_link(user)
    @user = user
    @token = user.generate_token_for(:email_sign_in)
    mail subject: "Your sign-in link", to: user.email_address
  end
end

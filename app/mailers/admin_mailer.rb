class AdminMailer < ApplicationMailer
  def test_email(user)
    @user = user
    mail subject: "Test email from Simple Aircraft Manager", to: user.email_address
  end
end

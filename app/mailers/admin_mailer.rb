class AdminMailer < ApplicationMailer
  def records_alert(user, backup, check)
    @backup = backup
    @check = check
    mail subject: "Records check needs attention", to: user.email_address
  end

  def test_email(user)
    @user = user
    mail subject: "Test email from Simple Aircraft Manager", to: user.email_address
  end
end

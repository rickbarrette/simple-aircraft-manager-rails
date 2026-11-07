class AdminMailer < ApplicationMailer
  def records_alert(user, backup, check)
    @backup = backup
    @check = check
    mail subject: "Records check needs attention", to: user.email_address
  end

  def offsite_alert(user, run)
    @run = run
    mail subject: run.kind == "restore_test" ? "Off-site restore test failed" : "Off-site backup failed", to: user.email_address
  end

  def test_email(user, via: "from Admin → About")
    @user = user
    @via = via
    mail subject: "Test email from Simple Aircraft Manager", to: user.email_address
  end
end

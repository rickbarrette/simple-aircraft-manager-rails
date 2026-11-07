class Admin::AboutController < ApplicationController
  before_action :require_admin!
  rate_limit to: 5, within: 1.minute, only: %i[test_email test_reminder], with: -> { redirect_to admin_about_path, alert: "Try again in a minute." }

  def show
    @info = SystemInfo.new
  end

  # This week's reminder for the current admin, now.
  def test_reminder
    return redirect_to(admin_about_path, alert: "Email isn't set up yet.") unless MailSettings.configured?
    unless ReminderMailer.anything_for?(current_user)
      return redirect_to admin_about_path, notice: "Nothing needs attention on the aircraft you own or your certificates, so there's no reminder to send."
    end
    ReminderMailer.weekly(current_user).deliver_now
    redirect_to admin_about_path, notice: "Reminder sent to #{current_user.email_address}."
  rescue StandardError => e
    redirect_to admin_about_path, alert: "Sending failed: #{e.class.name.demodulize}: #{e.message.to_s.squish.truncate(240)}"
  end

  # Sends right away (not via the job queue) so problems show up here.
  def test_email
    unless MailSettings.configured?
      return redirect_to admin_about_path, alert: "Email isn't set up yet: set SMTP_ADDRESS (and SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, MAIL_FROM)."
    end
    AdminMailer.test_email(current_user).deliver_now
    redirect_to admin_about_path, notice: "Test email sent to #{current_user.email_address}. If it doesn't arrive, check the spam folder."
  rescue StandardError => e # SMTP, DNS, TLS and timeout errors alike
    Rails.logger.warn("[test email] #{e.class}: #{e.message}")
    redirect_to admin_about_path, alert: "Sending failed: #{e.class.name.demodulize}: #{e.message.to_s.squish.truncate(240)}"
  end
end

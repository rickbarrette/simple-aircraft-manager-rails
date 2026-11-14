class Admin::AboutController < ApplicationController
  before_action :require_admin!
  rate_limit to: 5, within: 1.minute, only: %i[test_email test_reminder check_records], with: -> { redirect_to admin_about_path, alert: t("flash.admin_about.try_again_in_a") }

  def show
    @info = SystemInfo.new
  end

  # Back up and verify the records now (normally nightly).
  def check_records
    backup = DatabaseBackup.run!
    check = RecordsIntegrity.check!
    if backup.ok && check.ok
      redirect_to admin_about_path(anchor: "records"), notice: t("flash.admin_about.backed_up_and_checked")
    else
      redirect_to admin_about_path(anchor: "records"), alert: t("flash.admin_about.the_records_check_found")
    end
  end

  # This week's reminder for the current admin, now.
  def test_reminder
    return redirect_to(admin_about_path, alert: t("flash.admin_about.email_isn_t_set")) unless MailSettings.configured?
    unless ReminderMailer.anything_for?(current_user)
      return redirect_to admin_about_path, notice: t("flash.admin_about.nothing_needs_attention_on")
    end
    ReminderMailer.weekly(current_user).deliver_now
    redirect_to admin_about_path, notice: t("flash.admin_about.reminder_sent_to", email_address: current_user.email_address)
  rescue StandardError => e
    redirect_to admin_about_path, alert: t("flash.admin_about.sending_failed", error: e.class.name.demodulize, message: e.message.to_s.squish.truncate(240))
  end

  # Sends right away (not via the job queue) so problems show up here.
  def test_email
    unless MailSettings.configured?
      return redirect_to admin_about_path, alert: t("flash.admin_about.email_isn_t_set_2")
    end
    AdminMailer.test_email(current_user).deliver_now
    redirect_to admin_about_path, notice: t("flash.admin_about.test_email_sent_to", email_address: current_user.email_address)
  rescue StandardError => e # SMTP, DNS, TLS and timeout errors alike
    Rails.logger.warn("[test email] #{e.class}: #{e.message}")
    redirect_to admin_about_path, alert: t("flash.admin_about.sending_failed_2", error: e.class.name.demodulize, message: e.message.to_s.squish.truncate(240))
  end
end

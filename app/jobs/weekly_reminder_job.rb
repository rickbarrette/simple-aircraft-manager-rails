# Weekly email to aircraft owners listing what's overdue or coming due
# (inspections, ADs, components, expiring documents), deferred items, new
# ADs, and the user's own certificates that are about to expire.
# Nothing is sent when nothing needs attention, or when email isn't set up.
class WeeklyReminderJob < ApplicationJob
  queue_as :default

  def perform
    return unless MailSettings.configured?
    User.where(reminder_emails: true).find_each do |user|
      ReminderMailer.weekly(user).deliver_now if ReminderMailer.anything_for?(user)
    rescue StandardError => e
      Rails.logger.warn("[reminders] #{user.id}: #{e.class}: #{e.message}")
    end
  end
end

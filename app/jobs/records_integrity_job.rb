# Nightly: back up the database, then verify the records. Admins are emailed
# if either fails.
class RecordsIntegrityJob < ApplicationJob
  queue_as :default

  def perform
    backup = DatabaseBackup.run!
    check = RecordsIntegrity.check!
    return if backup.ok && check.ok
    return unless MailSettings.configured?
    User.active.where(admin: true).find_each { AdminMailer.records_alert(_1, backup, check).deliver_now }
  end
end

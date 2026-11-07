# Copies the latest verified database backup and new uploaded files to
# Google Drive (queued by the nightly RecordsIntegrityJob, or from Admin →
# Off-site Backup). Admins are emailed if it fails.
class OffsiteBackupJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "offsite_backup", duration: 12.hours if respond_to?(:limits_concurrency)

  def perform(kind = "backup")
    return unless OffsiteConnection.connected?
    run = kind == "restore_test" ? OffsiteBackup.restore_test! : backup
    return if run.nil? || run.ok || !MailSettings.configured?
    User.active.where(admin: true).find_each { AdminMailer.offsite_alert(_1, run).deliver_now }
  end

  private

  def backup
    latest = BackupRun.where(ok: true).order(:created_at, :id).last
    latest = DatabaseBackup.run! unless latest && latest.created_at > 1.day.ago && latest.path.present? && File.exist?(latest.path)
    return OffsiteRun.create!(kind: "backup", ok: false, message: "No verified database backup to copy: #{latest.message}") unless latest.ok
    OffsiteBackup.run!(latest.path)
  end
end

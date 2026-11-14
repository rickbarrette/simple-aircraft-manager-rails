# Admin → Off-site Backup: connect a Google Drive account the nightly
# backup is copied to, run a backup or a restore test now.
class Admin::OffsiteBackupsController < ApplicationController
  before_action :require_admin!
  before_action :set_connection

  def show
    @runs = OffsiteRun.order(created_at: :desc, id: :desc).limit(15)
    @files_copied = OffsiteFile.count
    @files_total = ActiveStorage::Blob.count
  end

  def update
    attrs = params.require(:offsite_connection).permit(:client_id, :client_secret)
    attrs.delete(:client_secret) if attrs[:client_secret].blank?
    changed_client = attrs[:client_id].present? && attrs[:client_id].strip != @connection.client_id
    @connection.disconnect! if changed_client && @connection.connected?
    @connection.update!(attrs.transform_values(&:strip))
    redirect_to admin_offsite_backup_path, notice: t("flash.admin_offsite_backups.saved_now_connect_your")
  end

  # Off to Google to grant access (a link, so no form-action CSP entry is needed).
  def connect
    return redirect_to(admin_offsite_backup_path, alert: t("flash.admin_offsite_backups.enter_the_google_oauth")) unless @connection.configured?
    session[:offsite_oauth_state] = state = SecureRandom.urlsafe_base64(24)
    redirect_to GoogleDriveClient.authorize_url(client_id: @connection.client_id, redirect_uri: @connection.redirect_uri, state: state),
                allow_other_host: true
  end

  def callback
    expected = session.delete(:offsite_oauth_state)
    unless expected.present? && params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
      return redirect_to(admin_offsite_backup_path, alert: t("flash.admin_offsite_backups.that_google_sign_in"))
    end
    return redirect_to(admin_offsite_backup_path, alert: t("flash.admin_offsite_backups.google_drive_wasn_t", error: params[:error])) if params[:error].present? || params[:code].blank?

    token = GoogleDriveClient.exchange_code(client_id: @connection.client_id, client_secret: @connection.client_secret,
                                            code: params[:code].to_s, redirect_uri: @connection.redirect_uri)
    @connection.update!(refresh_token: token, connected_by: current_user, connected_at: Time.current)
    drive = @connection.client
    @connection.update!(account_email: drive.account_email)
    @connection.ensure_folders!(drive)
    Rails.logger.info("[offsite] #{current_user.email_address} connected Google Drive #{@connection.account_email}")
    OffsiteBackupJob.perform_later
    redirect_to admin_offsite_backup_path, notice: t("flash.admin_offsite_backups.google_drive_connected_the", account_email: @connection.account_email)
  rescue GoogleDriveClient::Error => e
    redirect_to admin_offsite_backup_path, alert: t("flash.admin_offsite_backups.couldn_t_connect_google", message: e.message)
  end

  def destroy
    @connection.disconnect!
    Rails.logger.info("[offsite] #{current_user.email_address} disconnected Google Drive")
    redirect_to admin_offsite_backup_path, notice: t("flash.admin_offsite_backups.google_drive_disconnected_the")
  end

  def backup_now
    OffsiteBackupJob.perform_later
    redirect_to admin_offsite_backup_path, notice: t("flash.admin_offsite_backups.off_site_backup_started")
  end

  def restore_test
    OffsiteBackupJob.perform_later("restore_test")
    redirect_to admin_offsite_backup_path, notice: t("flash.admin_offsite_backups.restore_test_started_refresh")
  end

  private

  def set_connection = @connection = OffsiteConnection.current
end

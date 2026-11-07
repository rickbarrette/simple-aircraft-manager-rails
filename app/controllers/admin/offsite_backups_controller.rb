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
    redirect_to admin_offsite_backup_path, notice: "Saved. Now connect your Google account."
  end

  # Off to Google to grant access (a link, so no form-action CSP entry is needed).
  def connect
    return redirect_to(admin_offsite_backup_path, alert: "Enter the Google OAuth client ID and secret first.") unless @connection.configured?
    session[:offsite_oauth_state] = state = SecureRandom.urlsafe_base64(24)
    redirect_to GoogleDriveClient.authorize_url(client_id: @connection.client_id, redirect_uri: @connection.redirect_uri, state: state),
                allow_other_host: true
  end

  def callback
    expected = session.delete(:offsite_oauth_state)
    unless expected.present? && params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
      return redirect_to(admin_offsite_backup_path, alert: "That Google sign-in didn't match a request from here. Try connecting again.")
    end
    return redirect_to(admin_offsite_backup_path, alert: "Google Drive wasn't connected (#{params[:error]}).") if params[:error].present? || params[:code].blank?

    token = GoogleDriveClient.exchange_code(client_id: @connection.client_id, client_secret: @connection.client_secret,
                                            code: params[:code].to_s, redirect_uri: @connection.redirect_uri)
    @connection.update!(refresh_token: token, connected_by: current_user, connected_at: Time.current)
    drive = @connection.client
    @connection.update!(account_email: drive.account_email)
    @connection.ensure_folders!(drive)
    Rails.logger.info("[offsite] #{current_user.email_address} connected Google Drive #{@connection.account_email}")
    OffsiteBackupJob.perform_later
    redirect_to admin_offsite_backup_path, notice: "Google Drive connected (#{@connection.account_email}). The first off-site backup has started; it copies every uploaded file, so it can take a while."
  rescue GoogleDriveClient::Error => e
    redirect_to admin_offsite_backup_path, alert: "Couldn't connect Google Drive: #{e.message}"
  end

  def destroy
    @connection.disconnect!
    Rails.logger.info("[offsite] #{current_user.email_address} disconnected Google Drive")
    redirect_to admin_offsite_backup_path, notice: "Google Drive disconnected. The copies already there stay in your Drive."
  end

  def backup_now
    OffsiteBackupJob.perform_later
    redirect_to admin_offsite_backup_path, notice: "Off-site backup started. Refresh in a minute to see the result."
  end

  def restore_test
    OffsiteBackupJob.perform_later("restore_test")
    redirect_to admin_offsite_backup_path, notice: "Restore test started. Refresh in a minute to see the result."
  end

  private

  def set_connection = @connection = OffsiteConnection.current
end

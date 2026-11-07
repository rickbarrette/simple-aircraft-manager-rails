# Off-site backup to Google Drive (AC 120-78B 3.2.7). One row for the
# installation: the admin's own Google OAuth client and the refresh token
# from connecting an account. The app only has access to files it created
# (the drive.file scope).
class OffsiteConnection < ApplicationRecord
  ROOT_FOLDER = "Simple Aircraft Manager backups"

  belongs_to :connected_by, class_name: "User", optional: true
  encrypts :client_secret, :refresh_token

  # Tests swap in a fake Drive.
  class_attribute :client_factory, default: ->(conn) { GoogleDriveClient.new(client_id: conn.client_id, client_secret: conn.client_secret, refresh_token: conn.refresh_token) }

  def self.current = first || create!
  def self.connected? = current.connected?

  def configured? = client_id.present? && client_secret.present?
  def connected? = configured? && refresh_token.present?
  def client = client_factory.call(self)

  def redirect_uri = "#{Sso.app_url}/admin/offsite_backup/callback"

  def disconnect!
    begin
      GoogleDriveClient.revoke(refresh_token) if refresh_token.present?
    rescue GoogleDriveClient::Error
      nil # already revoked or unreachable; forget it anyway
    end
    update!(refresh_token: nil, account_email: nil, folder_id: nil, database_folder_id: nil, files_folder_id: nil, connected_at: nil)
  end

  # Folders in Drive, made on first use (again if someone deleted them).
  def ensure_folders!(drive)
    changes = {}
    root = folder_id if folder_id.present? && drive.folder?(folder_id)
    root ||= changes[:folder_id] = drive.create_folder("#{ROOT_FOLDER} (#{URI.parse(Sso.app_url).host})")
    { database_folder_id: "database", files_folder_id: "files" }.each do |column, name|
      id = self[column]
      next if id.present? && !changes.key?(:folder_id) && drive.folder?(id)
      changes[column] = drive.create_folder(name, parent: root)
    end
    update!(changes) if changes.any?
  end
end

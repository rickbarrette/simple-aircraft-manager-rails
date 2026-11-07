require "test_helper"

# Off-site backup to Google Drive (AC 120-78B 3.2.7).
class OffsiteBackupTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  # An in-memory Drive.
  class FakeDrive
    attr_reader :files, :folders

    def initialize = (@files = {}; @folders = {}; @n = 0)
    def account_email = "backups@example.com"
    def folder?(id) = @folders.key?(id)
    def create_folder(name, parent: nil) = "f#{@n += 1}".tap { @folders[_1] = [ name, parent ] }

    def upload(io, name:, parent:, size:, content_type: nil, properties: {})
      data = io.read
      raise "size mismatch" unless data.bytesize == size
      "d#{@n += 1}".tap { @files[_1] = { "name" => name, "parent" => parent, "data" => data, "appProperties" => properties } }
    end

    def list(parent) = @files.select { _2["parent"] == parent }.map { |id, f| { "id" => id, "name" => f["name"] } }
    def download(id, to:) = to.tap { _1.write(@files.fetch(id)["data"]); _1.rewind }
    def delete(id) = @files.delete(id)
  end

  setup do
    @admin = create_user("admin@example.com", admin: true)
    @a = create_aircraft(owner: @admin, tail_number: "N12345")
    @drive = FakeDrive.new
    drive = @drive
    @factory = OffsiteConnection.client_factory
    OffsiteConnection.client_factory = ->(_) { drive }
  end

  teardown { OffsiteConnection.client_factory = @factory }

  def connect!
    OffsiteConnection.current.update!(client_id: "id.apps.googleusercontent.com", client_secret: "secret", refresh_token: "refresh",
                                      account_email: "backups@example.com", connected_at: Time.current)
  end

  def database_snapshot
    path = Rails.root.join("tmp", "sam-offsite-test-#{SecureRandom.hex(4)}.sqlite3")
    db = SQLite3::Database.new(path.to_s)
    db.execute("CREATE TABLE logbook_entries (id integer)")
    db.execute("CREATE TABLE entry_signatures (id integer)")
    db.execute("INSERT INTO logbook_entries VALUES (1)")
    db.close
    path
  end

  test "an admin saves the OAuth client and connects through Google" do
    sign_in @admin
    get admin_offsite_backup_path
    assert_response :success
    assert_includes response.body, "/admin/offsite_backup/callback"
    patch admin_offsite_backup_path, params: { offsite_connection: { client_id: " id.apps.googleusercontent.com ", client_secret: "secret" } }
    conn = OffsiteConnection.current
    assert_equal "id.apps.googleusercontent.com", conn.client_id
    assert_not_equal "secret", conn.read_attribute_before_type_cast(:client_secret) # encrypted
    patch admin_offsite_backup_path, params: { offsite_connection: { client_id: "id.apps.googleusercontent.com", client_secret: "" } }
    assert_equal "secret", conn.reload.client_secret # blank keeps it

    get connect_admin_offsite_backup_path
    assert_match %r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth\?}, response.location
    query = Rack::Utils.parse_query(URI(response.location).query)
    assert_equal "https://www.googleapis.com/auth/drive.file", query["scope"]
    assert_equal "offline", query["access_type"]

    get callback_admin_offsite_backup_path, params: { state: "forged", code: "x" }
    assert_nil conn.reload.refresh_token

    get connect_admin_offsite_backup_path
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    stub_request(:post, GoogleDriveClient::TOKEN_URL).to_return(status: 200, body: { refresh_token: "refresh-1", access_token: "a", expires_in: 3600 }.to_json)
    assert_enqueued_with(job: OffsiteBackupJob) do
      get callback_admin_offsite_backup_path, params: { state: state, code: "auth-code" }
    end
    conn.reload
    assert conn.connected?
    assert_equal "refresh-1", conn.refresh_token
    assert_equal "backups@example.com", conn.account_email
    assert_equal 3, @drive.folders.size
    assert_equal conn.folder_id, @drive.folders[conn.files_folder_id].last

    stub_request(:post, GoogleDriveClient::REVOKE_URL).to_return(status: 200)
    delete admin_offsite_backup_path
    refute conn.reload.connected?
  end

  test "the backup copies the database and new files once, prunes old copies, and the restore test checks them" do
    connect!
    doc = @a.documents.create!(name: "Registration", doc_type: "REGISTRATION")
    doc.pages.attach(io: StringIO.new("scan one"), filename: "reg.pdf", content_type: "application/pdf")
    path = database_snapshot
    with_setting("offsite_backups_kept", 2) do
      3.times { |i| travel(i.minutes) { OffsiteBackup.run!(path) } }
    end
    run = OffsiteRun.latest_backup
    assert run.ok, run.message
    conn = OffsiteConnection.current
    assert_equal 2, @drive.list(conn.database_folder_id).size, OffsiteRun.pluck(:ok, :message, :details).inspect
    files = @drive.list(conn.files_folder_id)
    assert_equal [ doc.pages.first.blob.key ], files.map { _1["name"] } # copied once
    assert_equal "reg.pdf", @drive.files[files.first["id"]]["appProperties"][:filename]
    assert_equal 1, OffsiteRun.backups.where("files_uploaded > 0").count

    test_run = OffsiteBackup.restore_test!
    assert test_run.ok, test_run.message
    assert_includes test_run.message, "integrity check ok"
    assert_includes test_run.message, "1 of 1 sampled files match"

    @drive.files[files.first["id"]]["data"] = "tampered"
    refute OffsiteBackup.restore_test!.ok
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  test "failures are recorded and emailed to admins; procedures and audits use the Drive backup" do
    connect!
    def @drive.upload(*, **) = raise(GoogleDriveClient::AuthError, "Google Drive refused access; connect again")
    BackupRun.create!(ok: true, path: database_snapshot.to_s, message: "ok")
    assert_emails(1) { OffsiteBackupJob.perform_now }
    refute OffsiteRun.latest_backup.ok
    assert_includes ActionMailer::Base.deliveries.last.subject, "Off-site backup failed"

    policy = RecordkeepingPolicy.current
    policy.update!(operator_name: "Jane Pilot", responsible_name: "Jane Pilot", hosting_description: "Home server")
    assert policy.complete? # Drive stands in for the description
    item = RecordsAudit.new.auto_items.find { _1.key == "offsite" }
    refute item.passed
    sign_in @admin
    get draft_admin_procedures_path
    assert_includes response.body, "Google Drive (account backups@example.com"
    get admin_about_path
    assert_includes response.body, "Off-site backup"
  ensure
    File.delete(BackupRun.last.path) if BackupRun.last&.path && File.exist?(BackupRun.last.path)
  end

  test "the Drive client uploads with a resumable session and refreshes its token" do
    stub_request(:post, GoogleDriveClient::TOKEN_URL).with(body: hash_including("grant_type" => "refresh_token"))
      .to_return(status: 200, body: { access_token: "tok", expires_in: 3600 }.to_json)
    stub_request(:post, %r{\Ahttps://www\.googleapis\.com/upload/drive/v3/files\?.*uploadType=resumable})
      .with(headers: { "Authorization" => "Bearer tok", "X-Upload-Content-Length" => "5" })
      .to_return(status: 200, headers: { "Location" => "https://www.googleapis.com/upload/drive/v3/files?upload_id=abc" })
    stub_request(:put, "https://www.googleapis.com/upload/drive/v3/files?upload_id=abc").with(body: "hello")
      .to_return(status: 200, body: { id: "file-1" }.to_json)
    client = GoogleDriveClient.new(client_id: "id", client_secret: "s", refresh_token: "r")
    assert_equal "file-1", client.upload(StringIO.new("hello"), name: "x", parent: "p", size: 5)

    stub_request(:get, %r{/drive/v3/about}).to_return(status: 401, body: { error: { message: "Invalid Credentials" } }.to_json)
    assert_raises(GoogleDriveClient::AuthError) { client.account_email }
    stub_request(:post, GoogleDriveClient::TOKEN_URL).to_return(status: 400, body: { error: "invalid_grant" }.to_json)
    assert_raises(GoogleDriveClient::AuthError) { GoogleDriveClient.new(client_id: "id", client_secret: "s", refresh_token: "r").account_email }
  end

  private

  def with_setting(key, value)
    Setting.create!(key: key, value: value.to_s)
    yield
  end
end

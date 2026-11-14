require "zlib"

# Off-site copy to Google Drive (AC 120-78B 3.2.7), after the nightly
# database backup: the verified database snapshot (gzipped; the newest few
# kept) and every uploaded file not yet copied (never deleted off-site,
# so a file removed by mistake can still be recovered).
#
#   database/sam-20261108-033000.sqlite3.gz
#   files/<blob key>                        (appProperties: filename, checksum)
class OffsiteBackup
  SAMPLE_FILES = 3

  def self.run!(database_path) = new.run!(database_path)
  def self.restore_test! = new.restore_test!

  def initialize(connection = OffsiteConnection.current)
    @connection = connection
  end

  def run!(database_path)
    raise I18n.t("services.offsite_backup.not_connected") unless @connection.connected?
    drive = @connection.client
    @connection.ensure_folders!(drive)
    bytes = upload_database(drive, database_path)
    pruned = prune(drive)
    uploaded, failed = upload_files(drive)
    message = I18n.t("services.offsite_backup.uploaded", size: ActiveSupport::NumberHelper.number_to_human_size(bytes), count: uploaded.size)
    message += I18n.t("services.offsite_backup.failed", count: failed.size, files: failed.first(3).join("; ")) if failed.any?
    OffsiteRun.create!(kind: "backup", ok: failed.empty?, bytes: bytes + uploaded.sum, files_uploaded: uploaded.size, message: message,
                       details: { "account" => @connection.account_email, "pruned" => pruned, "failed" => failed.first(20) })
  rescue StandardError => e
    Rails.logger.error("[offsite] #{e.class}: #{e.message}")
    OffsiteRun.create!(kind: "backup", ok: false, message: "#{e.class.name.demodulize}: #{e.message}".truncate(500))
  end

  # Downloads the newest database copy from Drive, opens it and checks it,
  # and downloads a few random files and checks them against their checksums.
  def restore_test!
    raise I18n.t("services.offsite_backup.not_connected") unless @connection.connected?
    drive = @connection.client
    latest = drive.list(@connection.database_folder_id).select { _1["name"].end_with?(".sqlite3.gz") }.max_by { _1["name"] } or raise "no database copy in Google Drive yet"
    db_result = Dir.mktmpdir("sam-restore") { |dir| check_database(drive, latest, dir) }
    samples = OffsiteFile.includes(:blob).order(Arel.sql("RANDOM()")).limit(SAMPLE_FILES).to_a
    bad = samples.reject { check_file(drive, _1) }
    message = I18n.t("services.offsite_backup.restore_result", name: latest["name"], result: db_result, good: samples.size - bad.size, total: samples.size)
    OffsiteRun.create!(kind: "restore_test", ok: bad.empty?, message: message,
                       details: { "database" => latest["name"], "files_checked" => samples.map { _1.blob.filename.to_s }, "mismatched" => bad.map { _1.blob.filename.to_s } })
  rescue StandardError => e
    Rails.logger.error("[offsite restore test] #{e.class}: #{e.message}")
    OffsiteRun.create!(kind: "restore_test", ok: false, message: "#{e.class.name.demodulize}: #{e.message}".truncate(500))
  end

  private

  def upload_database(drive, path)
    Tempfile.create([ "sam-offsite", ".gz" ], binmode: true) do |gz|
      Zlib::GzipWriter.wrap(File.open(gz.path, "wb")) { |w| File.open(path, "rb") { IO.copy_stream(_1, w) } }
      size = File.size(gz.path)
      File.open(gz.path, "rb") do |io|
        drive.upload(io, name: "#{File.basename(path)}.gz", parent: @connection.database_folder_id, size: size, content_type: "application/gzip")
      end
      size
    end
  end

  def prune(drive)
    keep = Setting.integer("offsite_backups_kept")
    copies = drive.list(@connection.database_folder_id).select { _1["name"].start_with?("sam-") }.sort_by { _1["name"] }.reverse
    copies.drop(keep).each { drive.delete(_1["id"]) }.map { _1["name"] }
  end

  # Returns [sizes uploaded, failure messages].
  def upload_files(drive)
    uploaded = []
    failed = []
    ActiveStorage::Blob.where.not(id: OffsiteFile.select(:blob_id)).find_each do |blob|
      blob.open do |file|
        id = drive.upload(file, name: blob.key, parent: @connection.files_folder_id, size: blob.byte_size,
                                content_type: blob.content_type.presence || "application/octet-stream",
                                properties: { filename: blob.filename.to_s.first(100), checksum: blob.checksum.to_s })
        OffsiteFile.create!(blob: blob, drive_file_id: id, bytes: blob.byte_size)
        uploaded << blob.byte_size
      end
    rescue GoogleDriveClient::AuthError
      raise
    rescue StandardError => e
      failed << "#{blob.filename}: #{e.message.truncate(120)}"
    end
    [ uploaded, failed ]
  end

  def check_database(drive, file, dir)
    gz = File.join(dir, "db.sqlite3.gz")
    File.open(gz, "wb") { drive.download(file["id"], to: _1) }
    path = File.join(dir, "db.sqlite3")
    Zlib::GzipReader.open(gz) { |r| File.open(path, "wb") { IO.copy_stream(r, _1) } }
    db = SQLite3::Database.new(path, readonly: true)
    result = db.get_first_value("PRAGMA integrity_check")
    raise "integrity check of the downloaded copy failed: #{result}" unless result == "ok"
    entries, signatures = %w[logbook_entries entry_signatures].map { db.get_first_value("SELECT COUNT(*) FROM #{_1}") }
    I18n.t("services.offsite_backup.restore_db", entries: entries, signatures: signatures, entries_now: LogbookEntry.count, signatures_now: EntrySignature.count)
  ensure
    db&.close
  end

  def check_file(drive, offsite)
    io = drive.download(offsite.drive_file_id, to: StringIO.new(+"", "wb"))
    Digest::MD5.base64digest(io.string) == offsite.blob.checksum
  rescue GoogleDriveClient::Error
    false
  end
end

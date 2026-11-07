# Built-in backup of the main database (AC 120-78B 3.2.7): a consistent
# snapshot (SQLite's online backup API, safe while the app runs) in storage/backups,
# checked by opening it and running SQLite's integrity check, and the newest
# few kept. Uploaded files aren't copied (they're already in storage/ and,
# being deduplicated, cheap to back up with the rest of the volume).
class DatabaseBackup
  DIR = Rails.root.join("storage", "backups")

  def self.run! = new.run!

  def run!
    FileUtils.mkdir_p(DIR)
    path = DIR.join("sam-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.sqlite3")
    copy(path)
    message = verify(path)
    bytes = File.size(path)
    prune(keep_path: path)
    BackupRun.create!(ok: true, path: path.to_s, bytes: bytes, message: message)
  rescue StandardError => e
    Rails.logger.error("[backup] #{e.class}: #{e.message}")
    BackupRun.create!(ok: false, path: path&.to_s, message: "#{e.class.name.demodulize}: #{e.message}".truncate(500))
  end

  private

  def copy(path)
    source = ActiveRecord::Base.connection.raw_connection
    dest = SQLite3::Database.new(path.to_s)
    backup = SQLite3::Backup.new(dest, "main", source, "main")
    result = backup.step(-1)
    backup.finish
    raise "the database was busy (SQLite code #{result}); try again" unless result == SQLite3::Constants::ErrorCode::DONE
  ensure
    dest&.close
  end

  # Opens the copy and checks it: SQLite's integrity check, and the same
  # number of logbook entries and signatures as the live database.
  def verify(path)
    db = SQLite3::Database.new(path.to_s, readonly: true)
    result = db.get_first_value("PRAGMA integrity_check")
    raise "integrity check failed: #{result}" unless result == "ok"
    counts = %w[logbook_entries entry_signatures].map { |t| [ t, db.get_first_value("SELECT COUNT(*) FROM #{t}") ] }.to_h
    live = { "logbook_entries" => LogbookEntry.count, "entry_signatures" => EntrySignature.count }
    raise "record counts differ (#{counts} vs #{live})" unless counts == live
    "Verified: SQLite integrity check ok; #{counts['logbook_entries']} logbook entries, #{counts['entry_signatures']} signatures"
  ensure
    db&.close
  end

  # Keeps the newest few (by file time), always including the one just made.
  def prune(keep_path:)
    keep = Setting.integer("backups_kept")
    older = Dir[DIR.join("sam-*.sqlite3")].reject { _1 == keep_path.to_s }.sort_by { File.mtime(_1) }.reverse
    older.drop(keep - 1).each { File.delete(_1) }
  end
end

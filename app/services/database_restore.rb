require "zlib"

# Puts a database backup in place of the live database (bin/rails
# backups:restore), with the app stopped: a nightly copy from storage/backups,
# or a copy downloaded from Google Drive (.sqlite3.gz). The copy is checked
# first, and the current database is moved aside, never deleted.
class DatabaseRestore
  class Error < StandardError; end

  attr_reader :source, :target

  def self.newest_backup = Dir[DatabaseBackup::DIR.join("sam-*.sqlite3")].max_by { File.mtime(_1) }

  def self.live_database = File.expand_path(ActiveRecord::Base.connection_db_config.database.to_s, Rails.root)

  def initialize(source: nil, target: self.class.live_database, pidfile: Rails.root.join("tmp/pids/server.pid"))
    @pidfile = Pathname(pidfile)
    @source = source.presence || self.class.newest_backup or raise Error, "No backup found in #{DatabaseBackup::DIR}; give a file: backups:restore[path]"
    @target = File.expand_path(target.to_s, Rails.root)
    raise Error, "#{@source} doesn't exist" unless File.file?(@source)
  end

  # Opens the copy (unzipping a .gz to a temporary file) and checks it.
  # Returns a description; raises if it isn't a usable database.
  def check
    with_plain_copy { |path| describe(path) }
  end

  # Swaps the copy in. Returns the folder the previous database was moved to.
  def restore!
    raise Error, "The app seems to be running (#{running_reason}). Stop it first; with Docker: docker compose stop web, then docker compose run --rm web bin/rails backups:restore" if running_reason
    with_plain_copy do |path|
      describe(path)
      ActiveRecord::Base.connection_handler.clear_all_connections! if @target == self.class.live_database
      aside = File.join(File.dirname(@target), "pre-restore-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}")
      FileUtils.mkdir_p(aside)
      [ "", "-wal", "-shm" ].each { |ext| FileUtils.mv("#{@target}#{ext}", aside) if File.exist?("#{@target}#{ext}") }
      FileUtils.cp(path, @target)
      Rails.logger.warn("[restore] #{@target} replaced by #{@source}; previous database in #{aside}")
      aside
    end
  end

  private

  def with_plain_copy
    return yield(@source) unless @source.end_with?(".gz")
    Dir.mktmpdir("sam-restore") do |dir|
      path = File.join(dir, "restore.sqlite3")
      Zlib::GzipReader.open(@source) { |gz| File.open(path, "wb") { IO.copy_stream(gz, _1) } }
      yield path
    end
  rescue Zlib::GzipFile::Error => e
    raise Error, "#{@source} isn't a valid .gz file (#{e.message})"
  end

  def describe(path)
    db = SQLite3::Database.new(path, readonly: true)
    result = db.get_first_value("PRAGMA integrity_check")
    raise Error, "integrity check failed: #{result}" unless result == "ok"
    counts = %w[aircraft logbook_entries entry_signatures users].to_h { [ _1, db.get_first_value("SELECT COUNT(*) FROM #{_1}") ] }
    version = db.get_first_value("SELECT MAX(version) FROM schema_migrations")
    "#{File.basename(@source)}: SQLite integrity check ok; #{counts['aircraft']} aircraft, #{counts['logbook_entries']} logbook entries, " \
      "#{counts['entry_signatures']} signatures, #{counts['users']} users; schema #{version}"
  rescue SQLite3::Exception => e
    raise Error, "#{File.basename(@source)} isn't a usable database (#{e.message})"
  ensure
    db&.close
  end

  # A live server process (Puma's pid file) means the app is running.
  def running_reason
    return unless @pidfile.exist?
    pid = @pidfile.read.to_i
    Process.kill(0, pid) && "server process #{pid}" if pid.positive?
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end
end

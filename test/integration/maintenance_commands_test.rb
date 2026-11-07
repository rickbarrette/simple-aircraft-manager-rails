require "test_helper"
require "rake"

# Maintenance and recovery commands: restore, records check, doctor,
# sign everyone out, records package, test email, off-site.
class MaintenanceCommandsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @dir = Dir.mktmpdir("sam-maint")
    Rails.application.load_tasks if Rake::Task.tasks.none? { _1.name == "sam:doctor" }
  end

  teardown { FileUtils.rm_rf(@dir) }

  def rake(name, *args)
    Rake::Task[name].reenable
    out, = capture_io { Rake::Task[name].invoke(*args) }
    out
  end

  def sqlite(path, entries: 1)
    db = SQLite3::Database.new(path)
    %w[aircraft logbook_entries entry_signatures users].each { db.execute("CREATE TABLE #{_1} (id integer)") }
    db.execute("CREATE TABLE schema_migrations (version varchar)")
    db.execute("INSERT INTO schema_migrations VALUES ('20261108050000')")
    entries.times { db.execute("INSERT INTO logbook_entries VALUES (1)") }
    db.close
    path
  end

  test "restoring a backup checks it, keeps the current database aside, and refuses while the app runs" do
    source = sqlite(File.join(@dir, "sam-20261101-033000.sqlite3"), entries: 3)
    target = sqlite(File.join(@dir, "production.sqlite3"))
    File.write("#{target}-wal", "x")
    restore = DatabaseRestore.new(source: source, target: target, pidfile: File.join(@dir, "none.pid"))
    assert_includes restore.check, "3 logbook entries"
    aside = restore.restore!
    assert File.exist?(File.join(aside, "production.sqlite3"))
    assert File.exist?(File.join(aside, "production.sqlite3-wal"))
    refute File.exist?("#{target}-wal")
    assert_equal 3, SQLite3::Database.new(target).get_first_value("SELECT COUNT(*) FROM logbook_entries")

    gz = File.join(@dir, "sam-20261102.sqlite3.gz")
    Zlib::GzipWriter.open(gz) { |w| w.write(File.binread(source)) }
    assert_includes DatabaseRestore.new(source: gz, target: target).check, "3 logbook entries"

    File.write(File.join(@dir, "junk.sqlite3"), "not a database")
    assert_raises(DatabaseRestore::Error) { DatabaseRestore.new(source: File.join(@dir, "junk.sqlite3"), target: target).check }

    pidfile = File.join(@dir, "server.pid")
    File.write(pidfile, Process.pid.to_s)
    error = assert_raises(DatabaseRestore::Error) { DatabaseRestore.new(source: source, target: target, pidfile: pidfile).restore! }
    assert_includes error.message, "running"
  end

  test "records:check reports the backup and the records check" do
    backup = BackupRun.create!(ok: true, message: "Verified")
    DatabaseBackup.singleton_class.alias_method :original_run!, :run!
    DatabaseBackup.define_singleton_method(:run!) { backup }
    out = rake("records:check")
    assert_includes out, "Backup: ok: Verified"
    assert_match(/Records check: ok/, out)
  ensure
    DatabaseBackup.singleton_class.alias_method :run!, :original_run!
  end

  test "sam:doctor reports each area without failing on a healthy test setup" do
    stub_request(:any, /.*/).to_return(status: 200, body: "{}")
    _, checks = SystemDoctor.report
    names = checks.map(&:name)
    assert_includes names, "Database"
    assert_includes names, "Last backup"
    assert_equal :ok, checks.find { _1.name == "Database" }.status
    assert_equal :warn, checks.find { _1.name == "Last backup" }.status # never run
    assert_includes rake("sam:doctor"), "Records audit"
  end

  test "users:sign_out_all ends every session" do
    user = create_user("jane@example.com")
    sign_in user
    assert_includes rake("users:sign_out_all"), "Ended 1 sessions"
    get root_path
    assert_redirected_to new_session_path
  end

  test "sam:records_package writes the zip; email:test sends; off-site commands need Drive" do
    owner = create_user("owner@example.com")
    create_aircraft(owner: owner, tail_number: "N12345")
    path = File.join(@dir, "package.zip")
    assert_includes rake("sam:records_package", "n12345", path), "Wrote #{path}"
    assert Zip::File.open(path) { |z| z.find_entry("README.txt") }

    assert_emails(1) { rake("email:test", "someone@example.com") }
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "from the server's command line"

    assert_raises(SystemExit) { capture_io { Rake::Task["offsite:backup"].reenable; Rake::Task["offsite:backup"].invoke } }
  end
end

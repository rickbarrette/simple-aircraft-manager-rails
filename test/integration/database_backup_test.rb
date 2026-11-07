require "test_helper"

# Backups copy the live database with SQLite's online backup API, which can't
# run inside the transaction each test normally runs in: these tests commit
# for real and clean up after themselves.
class DatabaseBackupTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  self.use_transactional_tests = false

  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    @mech = create_user("mech@example.com").tap { _1.update!(name: "Sam Mechanic") }
    @ap = @mech.certificates.create!(kind: "AP", number: "7654321")
  end

  teardown do
    FileUtils.rm_rf(DatabaseBackup::DIR)
    [ EntrySignature, LogbookEntry ].each { _1.delete_all }
    [ RecordVersion, IntegrityCheck, BackupRun, AircraftEvent, AircraftRole, UserCertificate, Aircraft, Session, Setting, User ].each(&:delete_all)
  end

  def entry(**attrs)
    @a.logbook_entries.create!({ date: Date.new(2026, 10, 1), entry_type: "MAINTENANCE", text: "Changed oil", aircraft_hours_at_entry: 1000 }.merge(attrs))
  end

  test "the nightly job backs up and verifies the database, prunes old copies, and emails admins on trouble" do
    admin = create_user("admin@example.com", admin: true)
    entry
    Setting.update_integers("backups_kept" => "2")
    dir = DatabaseBackup::DIR
    FileUtils.rm_rf(dir)
    3.times { |i| travel(i.minutes) { DatabaseBackup.run! } }
    run = BackupRun.latest
    assert run.ok, run.message
    assert_match "Verified: SQLite integrity check ok; 1 logbook entries", run.message
    assert_equal 2, Dir[dir.join("sam-*.sqlite3")].size
    db = SQLite3::Database.new(run.path, readonly: true)
    assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM logbook_entries")
    db.close

    assert_no_emails { RecordsIntegrityJob.perform_now }
    assert [ BackupRun.latest.ok, IntegrityCheck.latest.ok ].all?, [ BackupRun.latest.message, IntegrityCheck.latest.problems ].inspect
    LogbookEntry.update_all(text: "x") # no signatures, so this alone isn't a problem
    EntrySigner.new(entry(date: Date.new(2026, 10, 2)), user: @mech, certificate: @ap, auth_method: "password").sign!
    LogbookEntry.where(date: Date.new(2026, 10, 2)).update_all(text: "tampered")
    assert_emails 1 do
      RecordsIntegrityJob.perform_now
    end
    assert_equal [ admin.email_address ], ActionMailer::Base.deliveries.last.to

    sign_in admin
    get admin_about_path
    assert_includes response.body, "Records integrity"
    assert_includes response.body, "changed after it was signed"
    post admin_check_records_path
    assert_redirected_to admin_about_path(anchor: "records")
  end
end

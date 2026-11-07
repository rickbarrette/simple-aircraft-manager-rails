# Maintenance and recovery commands. In Docker: docker compose exec web bin/rails <task>
# (backups:restore needs the app stopped: docker compose stop web, then
#  docker compose run --rm web bin/rails backups:restore).

namespace :sam do
  desc "Health report: settings, email, single sign-on, Google Drive, migrations, disk, jobs, backups, audit"
  task doctor: :environment do
    text, checks = SystemDoctor.report
    puts text
    exit 1 if checks.any? { _1.status == :fail }
  end

  desc "Write an aircraft's records package (entries with signatures, history, procedures, data) to a zip"
  task :records_package, %i[tail_number path] => :environment do |_, args|
    aircraft = Aircraft.find_by("UPPER(tail_number) = ?", args[:tail_number].to_s.upcase) or abort "No aircraft #{args[:tail_number].inspect}"
    package = RecordsPackage.new(aircraft, source: "command line")
    path = args[:path].presence || package.filename
    package.write_to(path)
    puts "Wrote #{path} (#{ActiveSupport::NumberHelper.number_to_human_size(File.size(path))})"
  end
end

namespace :records do
  desc "Back up the database now and check the records (history chains and every signature); exits 1 on a problem"
  task check: :environment do
    backup = DatabaseBackup.run!
    puts "Backup: #{backup.ok ? 'ok' : 'FAILED'}: #{backup.message}"
    check = RecordsIntegrity.check!
    puts "Records check: #{check.ok ? 'ok' : 'PROBLEMS'}: #{check.versions_checked} history entries and #{check.signatures_checked} signatures checked"
    Array(check.problems).first(50).each { puts "  - #{_1}" }
    exit 1 unless backup.ok && check.ok
  end
end

namespace :backups do
  desc "List the nightly database copies in storage/backups"
  task list: :environment do
    files = Dir[DatabaseBackup::DIR.join("sam-*.sqlite3")].sort_by { File.mtime(_1) }.reverse
    abort "No backups in #{DatabaseBackup::DIR}" if files.empty?
    files.each { puts "#{_1}  #{ActiveSupport::NumberHelper.number_to_human_size(File.size(_1))}  #{File.mtime(_1).utc.iso8601}" }
  end

  desc "Replace the database with a backup (newest nightly copy, or a file incl. a Google Drive .sqlite3.gz); app must be stopped. CONFIRM=yes to skip the prompt"
  task :restore, [ :file ] => :environment do |_, args|
    restore = DatabaseRestore.new(source: args[:file])
    puts "Restoring from: #{restore.check}"
    puts "Into:           #{restore.target}"
    unless ENV["CONFIRM"] == "yes"
      abort "Run again with CONFIRM=yes to go ahead." unless $stdin.tty?
      print "Replace the current database with this backup? The current one is kept aside. [y/N] "
      abort "Cancelled." unless $stdin.gets.to_s.strip.downcase.start_with?("y")
    end
    aside = restore.restore!
    puts "Restored. The previous database is in #{aside}."
    puts "Next: start the app (it applies any newer migrations), restore uploaded files if needed (bin/rails offsite:restore_files),"
    puts "then run bin/rails records:check and bin/rails sam:doctor."
  rescue DatabaseRestore::Error => e
    abort "Error: #{e.message}"
  end
end

namespace :users do
  desc "Sign every user out of every device (suspected compromise)"
  task sign_out_all: :environment do
    puts "Ended #{AccountRecovery.sign_out_all!} sessions. Everyone signs in again."
  end
end

namespace :email do
  desc "Send a test email to an address, to check the SMTP settings"
  task :test, [ :address ] => :environment do |_, args|
    address = args[:address].to_s.strip
    abort "Give an address: bin/rails \"email:test[you@example.com]\"" if address.blank?
    MailSettings.summary.each { |k, v| puts "#{k}: #{v}" }
    user = User.find_by(email_address: address.downcase) || User.new(email_address: address, name: address)
    AdminMailer.test_email(user, via: "from the server's command line").deliver_now
    puts "Sent to #{address}."
  rescue StandardError => e
    abort "Sending failed: #{e.class.name.demodulize}: #{e.message}"
  end
end

namespace :offsite do
  desc "Copy the latest backup and new files to Google Drive now"
  task backup: :environment do
    abort "Google Drive isn't connected (Admin → Off-site Backup)." unless OffsiteConnection.connected?
    run = OffsiteBackupJob.backup
    puts "#{run.ok ? 'OK' : 'FAILED'}: #{run.message}"
    exit 1 unless run.ok
  end

  desc "Download the newest database copy and a few files from Google Drive and check them"
  task restore_test: :environment do
    abort "Google Drive isn't connected (Admin → Off-site Backup)." unless OffsiteConnection.connected?
    run = OffsiteBackup.restore_test!
    puts "#{run.ok ? 'OK' : 'FAILED'}: #{run.message}"
    exit 1 unless run.ok
  end
end

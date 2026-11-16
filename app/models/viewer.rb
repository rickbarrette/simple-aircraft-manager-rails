# Viewer mode (SAM_VIEWER=true): a read-only copy of an aircraft archive for
# whoever receives a records package (the FAA, a buyer), with no sign-in. It's
# what the package's viewer/docker-compose.yml runs, on that person's own
# computer.
#
# - At start (bin/rails sam:viewer:prepare, from bin/docker-entrypoint), the
#   archive at SAM_VIEWER_ARCHIVE is imported, owned by a built-in account.
# - Everyone is that account (Authentication): no sign-in.
# - Nothing can be changed: requests other than GET/HEAD are refused
#   (ApplicationController), and no role permission applies (AircraftScoped).
#
# So that it can never open a real installation, it refuses to run when the
# database has any account other than the built-in one: setting SAM_VIEWER on
# a real server stops it rather than exposing its records.
module Viewer
  EMAIL = "viewer@sam-viewer.invalid".freeze

  class RealAccounts < StandardError
    def message = "SAM_VIEWER is on, but this database has user accounts: viewer mode is only for an empty " \
                  "copy made to look at an archive. Turn SAM_VIEWER off for a real installation."
  end

  def self.enabled? = ENV["SAM_VIEWER"] == "true"
  def self.archive = ENV["SAM_VIEWER_ARCHIVE"].presence
  # What was imported, for the banner (kept with the data).
  def self.info_path = Pathname(ENV["SAM_VIEWER_INFO"].presence || Rails.root.join("storage/viewer.json"))
  def self.real_accounts? = User.where.not(email_address: EMAIL).exists?

  # The built-in account everyone browses as (made when first needed). It
  # can't sign in by password: nobody knows it.
  def self.user
    User.find_or_create_by!(email_address: EMAIL) do |u|
      u.name = I18n.t("viewer.account_name")
      u.password = SecureRandom.base58(40)
    end
  end

  # Checks the database, then imports the archive the first time.
  def self.prepare!(output: $stdout)
    raise RealAccounts if real_accounts?
    owner = user
    if Aircraft.exists?
      output.puts "Viewer: already imported (#{Aircraft.ordered.pluck(:tail_number).join(', ')})."
    elsif archive.nil? || !File.file?(archive)
      output.puts "Viewer: no archive at SAM_VIEWER_ARCHIVE (#{archive.inspect}); nothing to show."
    else
      output.puts "Viewer: importing #{File.basename(archive)}…"
      preview = AircraftArchive::Importer.check(archive)
      result = AircraftArchive::Importer.new(archive, owner: owner).run
      File.write(info_path, { file: File.basename(archive), tail_number: result[:aircraft].tail_number,
                         exported_at: preview.exported_at&.iso8601 }.to_json)
      output.puts "Viewer: imported #{result[:aircraft].tail_number}: #{result[:counts].map { |k, n| "#{n} #{k.tr('_', ' ')}" }.join(', ')}"
    end
    output.puts "Viewer ready: open http://localhost:3000"
  end

  # What the banner says: the archive's file and when it was exported.
  def self.info
    JSON.parse(info_path.read) if info_path.file?
  rescue JSON::ParserError
    nil
  end
end

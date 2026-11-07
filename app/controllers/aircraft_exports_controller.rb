# Download an aircraft as a .sam.zip archive (owners and admins).
class AircraftExportsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  EXPORT_DIR = Rails.root.join("tmp/exports")

  def show
    exporter = AircraftArchive::Exporter.new(@aircraft, source: request.host)
    # A plain file (not a Tempfile) so it's still there while send_file streams it;
    # older exports are swept on the next one.
    FileUtils.mkdir_p(EXPORT_DIR)
    Dir[EXPORT_DIR.join("*.zip")].each { |old| File.delete(old) if File.mtime(old) < 1.hour.ago }
    path = EXPORT_DIR.join("#{SecureRandom.hex(12)}.zip").to_s
    exporter.write_to(path)
    log_event("aircraft", "Aircraft exported (.sam.zip)")
    send_file path, filename: exporter.filename, type: "application/zip", disposition: "attachment"
  end
end

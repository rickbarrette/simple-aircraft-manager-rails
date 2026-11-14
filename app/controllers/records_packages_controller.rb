# Download every record of an aircraft in one ZIP (owners).
class RecordsPackagesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def show
    package = RecordsPackage.new(@aircraft, source: request.host)
    dir = Rails.root.join("tmp", "packages")
    FileUtils.mkdir_p(dir)
    Dir[dir.join("*.zip")].each { |old| File.delete(old) if File.mtime(old) < 1.hour.ago }
    path = dir.join("#{SecureRandom.hex(12)}.zip").to_s
    package.write_to(path)
    log_event("aircraft", t("flash.records_packages.records_package_downloaded"))
    # Generic binary, not application/zip: Safari unzips zip downloads into a
    # folder ("Open safe files"); the package should stay one file to hand over.
    send_file path, filename: package.filename, type: "application/octet-stream", disposition: "attachment"
  end
end

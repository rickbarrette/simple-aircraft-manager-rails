# Owner-only bulk import of historical flights: upload → preview → confirm.
# The uploaded file is kept in tmp/imports between the two steps.
class FlightImportsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  MAX_SIZE = 10.megabytes
  DIR = Rails.root.join("tmp/imports")
  # Server-generated "<uuid>.<ext>"; anything else is rejected before touching the filesystem.
  TOKEN_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\.(xlsx|csv)\z/

  def new; end

  # Store the upload, then redirect to the preview (Turbo requires a redirect after a form POST).
  def create
    file = params[:file]
    return redirect_to(new_aircraft_flight_import_path(@aircraft), alert: "Choose a file to upload.") unless file.respond_to?(:path)
    return redirect_to(new_aircraft_flight_import_path(@aircraft), alert: "File is too large.") if file.size > MAX_SIZE

    ext = File.extname(file.original_filename).delete(".").downcase
    unless ext.in?(FlightImport::EXTENSIONS)
      return redirect_to new_aircraft_flight_import_path(@aircraft), alert: "Upload an .xlsx or .csv file."
    end

    cleanup_old_files
    FileUtils.mkdir_p(DIR)
    token = "#{SecureRandom.uuid}.#{ext}"
    FileUtils.cp(file.path, stored_path(token))
    redirect_to aircraft_flight_import_path(@aircraft, token: token, filename: file.original_filename,
                                            starting_tach: params[:starting_tach].presence,
                                            starting_hobbs: params[:starting_hobbs].presence)
  end

  # Preview.
  def show
    @token = params[:token].to_s
    return redirect_to_upload("Upload expired. Please upload the file again.") unless stored_file?(@token)

    @filename = params[:filename].to_s
    @starting_tach = params[:starting_tach].presence
    @starting_hobbs = params[:starting_hobbs].presence
    @import = build_import(@token, @filename)
    @import.rows # parse now so header errors surface here
  rescue FlightImport::Error => e
    redirect_to_upload(e.message)
  end

  def confirm
    token = params[:token].to_s
    return redirect_to_upload("Upload expired. Please upload the file again.") unless stored_file?(token)
    path = stored_path(token)

    import = build_import(token, params[:filename], starting_tach: params[:starting_tach], starting_hobbs: params[:starting_hobbs])
    count = import.import!(user: current_user, update_aircraft_hours: params[:update_aircraft_hours] == "1")
    File.delete(path)
    redirect_to aircraft_flight_logs_path(@aircraft), notice: "Imported #{count} flights."
  rescue FlightImport::Error => e
    redirect_to new_aircraft_flight_import_path(@aircraft), alert: e.message
  rescue AircraftGroundedError
    redirect_to aircraft_flight_logs_path(@aircraft),
                alert: "Flights imported, but aircraft hours weren't updated: the aircraft is grounded and enforcement is on."
  end

  private

  def stored_file?(token)
    TOKEN_FORMAT.match?(token) && File.exist?(stored_path(token))
  end

  def redirect_to_upload(message)
    redirect_to new_aircraft_flight_import_path(@aircraft), alert: message
  end

  def build_import(token, filename, starting_tach: @starting_tach, starting_hobbs: @starting_hobbs)
    FlightImport.new(@aircraft, path: stored_path(token), filename: filename,
                                starting_tach: starting_tach, starting_hobbs: starting_hobbs)
  end

  # Files are namespaced by aircraft so a token can't be replayed on another aircraft.
  def stored_path(token)
    DIR.join("#{@aircraft.id}-#{File.basename(token)}")
  end

  def cleanup_old_files
    Dir.glob(DIR.join("*")).each { |f| File.delete(f) if File.mtime(f) < 1.day.ago }
  end
end

# Owner-only bulk import of historical flights: upload → preview → confirm.
class FlightImportsController < ApplicationController
  include AircraftScoped
  include StoredUpload
  before_action :require_owner!

  def new; end

  # Store the upload, then redirect to the preview (Turbo requires a redirect after a form POST).
  def create
    token, error = store_upload(params[:file])
    return redirect_to_upload(error) if error
    redirect_to aircraft_flight_import_path(@aircraft, token: token, filename: params[:file].original_filename,
                                            starting_tach: params[:starting_tach].presence,
                                            starting_hobbs: params[:starting_hobbs].presence)
  end

  # Preview.
  def show
    @token = params[:token].to_s
    return redirect_to_upload(t("flash.uploads.expired")) unless stored_file?(@token)

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
    return redirect_to_upload(t("flash.uploads.expired")) unless stored_file?(token)

    import = build_import(token, params[:filename], starting_tach: params[:starting_tach], starting_hobbs: params[:starting_hobbs])
    count = import.import!(user: current_user, update_aircraft_hours: params[:update_aircraft_hours] == "1")
    discard_upload(token)
    redirect_to aircraft_flight_logs_path(@aircraft), notice: t("flash.flight_imports.imported_flights", count: count)
  rescue FlightImport::Error => e
    redirect_to new_aircraft_flight_import_path(@aircraft), alert: e.message
  rescue AircraftGroundedError
    redirect_to aircraft_flight_logs_path(@aircraft),
                alert: t("flash.flight_imports.flights_imported_but_aircraft")
  end

  private

  def redirect_to_upload(message)
    redirect_to new_aircraft_flight_import_path(@aircraft), alert: message
  end

  def build_import(token, filename, starting_tach: @starting_tach, starting_hobbs: @starting_hobbs)
    FlightImport.new(@aircraft, path: stored_path(token), filename: filename,
                                starting_tach: starting_tach, starting_hobbs: starting_hobbs)
  end
end

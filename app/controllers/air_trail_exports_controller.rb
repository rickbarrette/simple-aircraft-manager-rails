# Download the aircraft's flights as an AirTrail import file.
class AirTrailExportsController < ApplicationController
  include AircraftScoped

  def new
    @export = build_export
  end

  def create
    @export = build_export
    if @export.valid?
      send_data @export.to_json, filename: @export.filename, type: "application/json", disposition: "attachment"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def build_export
    AirTrailExport.new(@aircraft, username: params[:username].presence || default_username,
                                  aircraft_type: params[:aircraft_type],
                                  only_user: params[:scope] == "mine" ? current_user : nil)
  end

  # A reasonable guess for the AirTrail username: the part of the email before "@".
  def default_username = current_user.email_address.to_s.split("@").first.to_s.gsub(/[^A-Za-z0-9._-]/, "").first(20)
end

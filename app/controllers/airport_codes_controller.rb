# Flights → Standardize airport codes (owners).
class AirportCodesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def show
    @standardizer = AirportCodeStandardizer.new(@aircraft)
  end

  def update
    codes = Array(params[:codes]).map(&:to_s)
    standardizer = AirportCodeStandardizer.new(@aircraft)
    # Only codes that are actually unknown in this log, and only the ticked ones.
    fixes = params.fetch(:fixes, {}).permit(*standardizer.unknown.map(&:code)).to_h
                  .select { |code, _| Array(params[:fix]).include?(code) }
    updated = standardizer.apply!(codes, fixes: fixes)
    redirect_to aircraft_flight_logs_path(@aircraft), notice: "Updated #{updated} airport entries across your flights."
  end
end

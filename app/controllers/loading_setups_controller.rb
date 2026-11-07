# The aircraft's loading stations (arms) and CG envelope, from the POH, for
# the loading calculator.
class LoadingSetupsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def edit
    @setup = @aircraft.loading_setup
  end

  def update
    permitted = params.fetch(:setup, {}).permit(:fuel_lb_per_gal, stations: %i[name arm max fuel], envelope: %i[weight cg])
    @setup = LoadingSetup.from_params(permitted.to_h)
    if @setup.valid?
      @aircraft.update!(loading_stations: @setup.stations_json, cg_envelope: @setup.envelope)
      log_event("aircraft", "Loading stations and CG envelope updated")
      redirect_to aircraft_weight_balance_records_path(@aircraft), notice: "Loading setup saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end

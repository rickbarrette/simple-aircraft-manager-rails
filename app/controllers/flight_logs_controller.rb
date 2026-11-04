class FlightLogsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, only: :destroy

  def index
    @flight_logs = @aircraft.flight_logs.recent_first.includes(:user)
  end

  def show
    @flight_log = @aircraft.flight_logs.find(params[:id])
  end

  def new
    @flight_log = @aircraft.flight_logs.new(date: Date.current, tach_out: @aircraft.tach_time,
                                            hobbs_out: @aircraft.hobbs_time)
  end

  def create
    @flight_log = @aircraft.flight_logs.new(flight_log_params)
    if @flight_log.valid?
      HoursService.new(@aircraft).log_flight!(@flight_log)
      redirect_to aircraft_flight_logs_path(@aircraft), notice: "Flight logged (#{@flight_log.tach_time} hrs)."
    else
      render :new, status: :unprocessable_entity
    end
  rescue AircraftGroundedError => e
    flash.now[:alert] = e.message
    render :new, status: :conflict
  end

  # Deleting a flight does not roll back hours; correct those with an hours update.
  def destroy
    @aircraft.flight_logs.find(params[:id]).destroy!
    log_event("flight", "Flight log deleted")
    redirect_to aircraft_flight_logs_path(@aircraft), notice: "Flight log deleted. Aircraft hours were not changed."
  end

  private

  def flight_log_params
    params.require(:flight_log).permit(
      :date, :tach_time, :tach_out, :tach_in, :hobbs_time, :hobbs_out, :hobbs_in,
      :departure_location, :destination_location, :route, :oil_added, :oil_added_type,
      :oil_level_after, :fuel_added, :fuel_added_type, :fuel_level_after, :notes, :track_log
    )
  end
end

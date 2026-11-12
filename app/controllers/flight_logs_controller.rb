class FlightLogsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, only: :destroy
  before_action :set_flight_log, only: %i[show engine_data_series attach_engine_data remove_engine_data]
  before_action :require_engine_data_access!, only: %i[attach_engine_data remove_engine_data]
  helper_method :manage_engine_data?

  DAYS_PER_PAGE = 30

  # The flight log a page of days at a time; the rest load as you scroll
  # (each page ends in a lazy frame that fetches the next).
  def index
    @page = [ params[:page].to_i, 1 ].max
    dates = @aircraft.flight_logs.distinct.order(date: :desc)
                     .offset((@page - 1) * DAYS_PER_PAGE).limit(DAYS_PER_PAGE + 1).pluck(:date)
    @more = dates.size > DAYS_PER_PAGE
    logs = @aircraft.flight_logs.where(date: dates.first(DAYS_PER_PAGE))
                    .includes(:user).with_attached_track_log.with_attached_engine_data
    @days = FlightDay.group(logs)
    return render(partial: "flight_logs/days", locals: { days: @days, page: @page, more: @more }) if turbo_frame_request?

    @stats = FlightStats.new(@aircraft)
  end

  def show
    begin
      @track = TrackParser.parse_attachment(@flight_log.track_log)
    rescue TrackParser::Error => e
      @track_error = "Couldn't read track: #{e.message}"
    end
    begin
      @engine_data = EngineDataParser.parse_attachment(@flight_log.engine_data)
    rescue EngineDataParser::Error, ActiveStorage::FileNotFoundError => e
      @engine_data_error = "Couldn't read engine data: #{e.message}"
    end
    @air_trail_connection = @flight_log.user&.air_trail_connection
    @air_trail_sync = @flight_log.air_trail_syncs.first
  end

  # JSON for the interactive engine chart viewer (loaded when a chart is clicked).
  def engine_data_series
    recording = EngineDataParser.parse_attachment(@flight_log.engine_data) or return head(:not_found)
    return unless stale?(etag: [ @flight_log.engine_data.blob.key, EngineDataParser::CACHE_VERSION ], public: false)
    render json: recording.detail.merge(groups: helpers.engine_chart_groups(recording))
  rescue EngineDataParser::Error, ActiveStorage::FileNotFoundError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def new
    # Aircraft almost always depart from where they last landed.
    last = @aircraft.flight_logs.where.not(destination_location: [ nil, "" ]).recent_first.first
    @flight_log = @aircraft.flight_logs.new(date: Date.current, tach_out: @aircraft.tach_time,
                                            hobbs_out: @aircraft.hobbs_time,
                                            departure_location: last&.destination_location)
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

  def attach_engine_data
    file = params.dig(:flight_log, :engine_data)
    return redirect_to(aircraft_flight_log_path(@aircraft, @flight_log), alert: "Choose an engine data file.") if file.blank?

    @flight_log.engine_data = file
    if @flight_log.save
      redirect_to aircraft_flight_log_path(@aircraft, @flight_log), notice: "Engine data attached."
    else
      redirect_to aircraft_flight_log_path(@aircraft, @flight_log), alert: @flight_log.errors.full_messages.to_sentence
    end
  end

  def remove_engine_data
    @flight_log.engine_data.purge_later
    redirect_to aircraft_flight_log_path(@aircraft, @flight_log), notice: "Engine data removed."
  end

  # Deleting a flight does not roll back hours; correct those with an hours update.
  def destroy
    @aircraft.flight_logs.find(params[:id]).destroy!
    log_event("flight", "Flight log deleted")
    redirect_to aircraft_flight_logs_path(@aircraft), notice: "Flight log deleted. Aircraft hours were not changed."
  end

  private

  def set_flight_log
    @flight_log = @aircraft.flight_logs.find(params[:id])
  end

  # Owners, or the pilot who logged the flight.
  def manage_engine_data?
    owner? || (@flight_log.user_id.present? && @flight_log.user_id == current_user.id)
  end

  def require_engine_data_access!
    return if manage_engine_data?
    redirect_to aircraft_flight_log_path(@aircraft, @flight_log), alert: "Only owners or the flight's pilot can do that."
  end

  def flight_log_params
    params.require(:flight_log).permit(
      :date, :tach_time, :tach_out, :tach_in, :hobbs_time, :hobbs_out, :hobbs_in,
      :departure_location, :destination_location, :route, :oil_added, :oil_added_type,
      :oil_level_after, :fuel_added, :fuel_added_type, :fuel_level_after, :notes, :track_log, :engine_data
    )
  end
end

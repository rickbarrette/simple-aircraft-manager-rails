class AircraftController < ApplicationController
  include AircraftScoped
  skip_before_action :set_aircraft, only: %i[index new create]
  before_action :require_owner!, only: %i[edit update destroy]

  def index
    @aircraft_list = current_user.accessible_aircraft.ordered.with_attached_picture
  end

  def show
    @airworthiness = @aircraft.airworthiness
    @active_squawks = @aircraft.squawks.active.by_priority.includes(:component, :reported_by).with_attached_attachments
    @recent_events = @aircraft.events.includes(:user).limit(8)
    @notes = @aircraft.notes.recent_first.includes(:user).limit(5)
    @oil = ConsumptionStats.new(@aircraft, "oil")
    @fuel = ConsumptionStats.new(@aircraft, "fuel")
    last = @aircraft.flight_logs.recent_first.first
    @last_day = last && @aircraft.flight_logs.where(date: last.date).order(:created_at).to_a
  end

  def new
    @aircraft = Aircraft.new
  end

  def create
    @aircraft = Aircraft.new(aircraft_params)
    Aircraft.transaction do
      @aircraft.save!
      @aircraft.roles.create!(user: current_user, role: "owner")
      @aircraft.log_event!("aircraft", "Aircraft created")
    end
    redirect_to @aircraft, notice: t("flash.aircraft.added", tail_number: @aircraft.tail_number)
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @aircraft.update(aircraft_params)
      log_event("aircraft", t("flash.aircraft.aircraft_details_updated"))
      redirect_to @aircraft, notice: t("flash.aircraft.aircraft_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @aircraft.destroy!
    redirect_to root_path, notice: t("flash.aircraft.deleted", tail_number: @aircraft.tail_number)
  end

  # Pilots and above: set absolute tach/hobbs readings.
  def update_hours
    before = { tach: @aircraft.tach_time.to_d, hobbs: @aircraft.hobbs_time.to_d }
    HoursService.new(@aircraft).update_hours!(tach_time: params.require(:tach_time), hobbs_time: params[:hobbs_time])
    redirect_to @aircraft, notice: hours_notice(before)
  rescue AircraftGroundedError => e
    redirect_to @aircraft, alert: e.message
  rescue ArgumentError
    redirect_to @aircraft, alert: t("flash.aircraft.enter_a_valid_tach")
  end

  private

  # "Tach 4,211.6 → 4,213.0 (+1.4). In-service components moved +1.4 hrs; no flight was logged."
  def hours_notice(before)
    after = { tach: @aircraft.tach_time.to_d, hobbs: @aircraft.hobbs_time.to_d }
    signed = ->(d) { "#{d.negative? ? '−' : '+'}#{helpers.hours(d.abs)}" }
    changes = %i[tach hobbs].filter_map do |meter|
      d = after[meter] - before[meter]
      t("flash.aircraft.meter_changed", meter: Aircraft::TIME_BASES[meter.to_s], from: helpers.hours(before[meter]), to: helpers.hours(after[meter]), delta: signed.(d)) unless d.zero?
    end
    moved = @aircraft.hobbs? ? after[:hobbs] - before[:hobbs] : after[:tach] - before[:tach]
    return t("flash.aircraft.hours_unchanged") if changes.empty?
    t(moved.negative? ? "flash.aircraft.hours_corrected" : "flash.aircraft.hours_updated", changes: changes.join(" · "), delta: signed.(moved))
  end

  def aircraft_param = params[:id]

  def aircraft_params
    params.require(:aircraft).permit(
      :tail_number, :make, :model, :serial_number, :description, :purchased, :status,
      :tach_time, :tach_time_offset, :hobbs_time, :hobbs_time_offset,
      :airworthiness_enforcement, :picture, :icao_type, :time_basis, :electronic_records_since
    )
  end
end

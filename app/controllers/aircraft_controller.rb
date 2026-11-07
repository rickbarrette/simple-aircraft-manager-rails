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
    redirect_to @aircraft, notice: "#{@aircraft.tail_number} added."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @aircraft.update(aircraft_params)
      log_event("aircraft", "Aircraft details updated")
      redirect_to @aircraft, notice: "Aircraft updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @aircraft.destroy!
    redirect_to root_path, notice: "#{@aircraft.tail_number} deleted."
  end

  # Pilots and above: set absolute tach/hobbs readings.
  def update_hours
    delta = HoursService.new(@aircraft).update_hours!(
      tach_time: params.require(:tach_time), hobbs_time: params[:hobbs_time]
    )
    redirect_to @aircraft, notice: "Hours updated (#{delta >= 0 ? '+' : ''}#{delta})."
  rescue AircraftGroundedError => e
    redirect_to @aircraft, alert: e.message
  rescue ArgumentError
    redirect_to @aircraft, alert: "Enter a valid tach reading."
  end

  private

  def aircraft_param = params[:id]

  def aircraft_params
    params.require(:aircraft).permit(
      :tail_number, :make, :model, :serial_number, :description, :purchased, :status,
      :tach_time, :tach_time_offset, :hobbs_time, :hobbs_time_offset,
      :airworthiness_enforcement, :picture, :icao_type, :time_basis, :electronic_records_since
    )
  end
end

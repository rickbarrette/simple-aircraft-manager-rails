class SquawksController < ApplicationController
  include AircraftScoped
  # Pilots may create squawks; editing/resolving needs an owner.
  before_action :require_owner!, except: %i[index new create]
  before_action :set_squawk, only: %i[edit update destroy resolve reopen]

  def index
    @active = @aircraft.squawks.active.by_priority.includes(:component, :reported_by)
    @resolved = @aircraft.squawks.resolved.order(resolved_at: :desc).includes(:component).limit(100)
  end

  def new
    @squawk = @aircraft.squawks.new(priority: 1)
  end

  def create
    @squawk = @aircraft.squawks.new(squawk_params.merge(reported_by: current_user))
    if @squawk.save
      log_event("squawk", "Squawk reported: #{@squawk.priority_label}", notes: @squawk.issue_reported.truncate(200))
      redirect_to aircraft_squawks_path(@aircraft), notice: "Squawk reported."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @squawk.update(squawk_params)
      log_event("squawk", "Squawk updated")
      redirect_to aircraft_squawks_path(@aircraft), notice: "Squawk updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def resolve
    @squawk.resolve!(notes: params[:resolution_notes])
    log_event("squawk", "Squawk resolved", notes: @squawk.issue_reported.truncate(200))
    redirect_back fallback_location: aircraft_squawks_path(@aircraft), notice: "Squawk resolved."
  end

  def reopen
    @squawk.update!(resolved: false, resolved_at: nil)
    log_event("squawk", "Squawk reopened")
    redirect_to aircraft_squawks_path(@aircraft), notice: "Squawk reopened."
  end

  def destroy
    @squawk.destroy!
    log_event("squawk", "Squawk deleted")
    redirect_to aircraft_squawks_path(@aircraft), notice: "Squawk deleted."
  end

  private

  def set_squawk = @squawk = @aircraft.squawks.find(params[:id])

  def squawk_params
    params.require(:squawk).permit(:priority, :issue_reported, :component_id, :notes, :attachment)
  end
end

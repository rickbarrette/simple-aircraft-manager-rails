class SquawksController < ApplicationController
  include AircraftScoped
  # Pilots may create squawks; editing/resolving needs an owner.
  before_action :require_owner!, except: %i[index new create]
  before_action :set_squawk, only: %i[edit update destroy resolve reopen]

  def index
    @active = @aircraft.squawks.active.by_priority.includes(:component, :reported_by).with_attached_attachments
    @resolved = @aircraft.squawks.resolved.order(resolved_at: :desc).includes(:component).with_attached_attachments.limit(100)
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
    @squawk.assign_attributes(squawk_params.except(:attachments))
    change_attachments
    if @squawk.save
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

  # Adds uploads and drops ticked files in one change, so nothing is saved
  # (or purged) unless the whole update validates.
  def change_attachments
    added = Array(squawk_params[:attachments]).compact_blank
    removed = Array(params[:remove_attachment_ids]).map(&:to_s)
    return if added.empty? && removed.empty?
    kept = @squawk.attachments.reject { removed.include?(_1.id.to_s) }.map(&:blob)
    @squawk.attachments = kept + added
  end

  def squawk_params
    params.require(:squawk).permit(:priority, :issue_reported, :component_id, :notes, attachments: [])
          .tap { |p| p[:component_id] = scoped_id(@aircraft.components, p[:component_id]) if p.key?(:component_id) }
  end
end

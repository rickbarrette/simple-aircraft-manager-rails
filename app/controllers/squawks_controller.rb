class SquawksController < ApplicationController
  include AircraftScoped
  # Pilots may create squawks and defer inoperative items (91.213(d) lets the
  # pilot decide); editing and resolving need an owner.
  before_action :require_owner!, except: %i[index new create deferral defer]
  before_action :set_squawk, only: %i[edit update destroy resolution resolve reopen deferral defer undefer]

  def index
    @active = @aircraft.squawks.active.by_priority.includes(:component, :reported_by).with_attached_attachments
    @resolved = @aircraft.squawks.resolved.order(resolved_at: :desc).includes(:component, :logbook_entry).with_attached_attachments.limit(100)
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

  # Resolve form: record the fix in the logbook (who returned it to
  # service, 43.9), link an existing entry, or just close the squawk.
  def resolution
    @entry = @aircraft.logbook_entries.new(date: Date.current, entry_type: "MAINTENANCE", log_type: "AC",
                                           aircraft_hours_at_entry: @aircraft.current_hours,
                                           text: "Corrected: #{@squawk.issue_reported}", component: @squawk.component,
                                           component_hours_at_entry: @squawk.component&.hours_in_service,
                                           component_since_overhaul_at_entry: @squawk.component&.hours_since_overhaul)
    @entry.log_type = "ENG" if @squawk.component&.engine?
    @entry.log_type = "PROP" if @squawk.component&.propeller?
  end

  def resolve
    entry =
      case params[:logbook]
      when "new"
        @entry = @aircraft.logbook_entries.new(resolution_entry_params.merge(entry_type: "MAINTENANCE"))
        @entry.assign_parts(params.fetch(:logbook_entry, {}).permit(parts: {})[:parts]&.to_h || {}, @aircraft)
        return render(:resolution, status: :unprocessable_entity) unless @entry.save
        log_event("logbook", "Logbook entry added: #{@entry.date}")
        @entry
      when "existing" then @aircraft.logbook_entries.find_by(id: params[:logbook_entry_id])
      end
    @squawk.resolve!(notes: params[:resolution_notes], logbook_entry: entry)
    log_event("squawk", "Squawk resolved", notes: @squawk.issue_reported.truncate(200))
    redirect_to aircraft_squawks_path(@aircraft), notice: "Squawk resolved#{' and recorded in the logbook' if entry}."
  end

  def deferral; end

  def defer
    if @squawk.defer(checks: params[:checks], name: params[:deferred_by_name], role: params[:deferred_by_role],
                     action: params[:deferral_action], notes: params[:deferral_notes])
      log_event("squawk", "Inoperative item deferred (91.213(d))", notes: @squawk.issue_reported.truncate(200))
      redirect_to aircraft_squawks_path(@aircraft), notice: "Deferred. Keep the placard in place until it's fixed."
    else
      render :deferral, status: :unprocessable_entity
    end
  end

  def undefer
    @squawk.undefer!
    log_event("squawk", "Deferral removed", notes: @squawk.issue_reported.truncate(200))
    redirect_to aircraft_squawks_path(@aircraft), notice: "Deferral removed."
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

  def resolution_entry_params
    p = params.require(:logbook_entry).permit(:date, :log_type, :text, :aircraft_hours_at_entry, :signoff_person,
                                              :signoff_certificate_type, :signoff_certificate_number, :signoff_location,
                                              :component_id, :component_hours_at_entry, :component_since_overhaul_at_entry)
    p[:component_id] = scoped_id(@aircraft.components, p[:component_id]) if p.key?(:component_id)
    p
  end

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

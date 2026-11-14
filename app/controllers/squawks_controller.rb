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
    # Already received (sent again from the offline queue): don't report it twice.
    if (key = params.dig(:squawk, :client_key).to_s.presence) && @aircraft.squawks.exists?(client_key: key.first(64))
      return redirect_to(aircraft_squawks_path(@aircraft), notice: t("flash.squawks.already_reported"))
    end
    @squawk = @aircraft.squawks.new(squawk_params.merge(reported_by: current_user))
    if @squawk.save
      log_event("squawk", t("flash.squawks.squawk_reported_2", priority_label: @squawk.priority_label), notes: @squawk.issue_reported.truncate(200))
      if @squawk.grounding?
        PushNotifier.notify(@aircraft.users.merge(User.active).where.not(id: current_user.id), :grounding_squawk, path: aircraft_squawks_path(@aircraft),
                            tag: "squawk-#{@squawk.id}", tail: @aircraft.tail_number, issue: @squawk.issue_reported.truncate(120))
      end
      redirect_to aircraft_squawks_path(@aircraft), notice: t("flash.squawks.squawk_reported")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @squawk.assign_attributes(squawk_params.except(:attachments))
    change_attachments
    if @squawk.save
      log_event("squawk", t("flash.squawks.squawk_updated_2"))
      redirect_to aircraft_squawks_path(@aircraft), notice: t("flash.squawks.squawk_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Resolve form: record the fix in the logbook (who returned it to
  # service, 43.9), link an existing entry, or just close the squawk.
  def resolution
    @entry = @aircraft.logbook_entries.new(date: Date.current, entry_type: "MAINTENANCE", log_type: "AC",
                                           aircraft_hours_at_entry: @aircraft.current_hours,
                                           text: t("flash.squawks.corrected_text", issue: @squawk.issue_reported), component: @squawk.component,
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
        log_event("logbook", t("flash.squawks.logbook_entry_added", date: @entry.date))
        @entry
      when "existing" then @aircraft.logbook_entries.find_by(id: params[:logbook_entry_id])
      end
    @squawk.resolve!(notes: params[:resolution_notes], logbook_entry: entry)
    log_event("squawk", t("flash.squawks.squawk_resolved_2"), notes: @squawk.issue_reported.truncate(200))
    redirect_to aircraft_squawks_path(@aircraft), notice: t(entry ? "flash.squawks.resolved_logged" : "flash.squawks.squawk_resolved")
  end

  def deferral; end

  def defer
    if @squawk.defer(checks: params[:checks], name: params[:deferred_by_name], role: params[:deferred_by_role],
                     action: params[:deferral_action], notes: params[:deferral_notes])
      log_event("squawk", t("flash.squawks.inoperative_item_deferred_91"), notes: @squawk.issue_reported.truncate(200))
      redirect_to aircraft_squawks_path(@aircraft), notice: t("flash.squawks.deferred_keep_the_placard")
    else
      render :deferral, status: :unprocessable_entity
    end
  end

  def undefer
    @squawk.undefer!
    log_event("squawk", t("flash.squawks.deferral_removed_2"), notes: @squawk.issue_reported.truncate(200))
    redirect_to aircraft_squawks_path(@aircraft), notice: t("flash.squawks.deferral_removed")
  end

  def reopen
    @squawk.update!(resolved: false, resolved_at: nil)
    log_event("squawk", t("flash.squawks.squawk_reopened_2"))
    redirect_to aircraft_squawks_path(@aircraft), notice: t("flash.squawks.squawk_reopened")
  end

  def destroy
    @squawk.destroy!
    log_event("squawk", t("flash.squawks.squawk_deleted_2"))
    redirect_to aircraft_squawks_path(@aircraft), notice: t("flash.squawks.squawk_deleted")
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
    params.require(:squawk).permit(:priority, :issue_reported, :component_id, :notes, :client_key, attachments: [])
          .tap { |p| p[:component_id] = scoped_id(@aircraft.components, p[:component_id]) if p.key?(:component_id) }
          .tap { |p| p[:client_key] = p[:client_key].to_s.first(64).presence if p.key?(:client_key) }
  end
end

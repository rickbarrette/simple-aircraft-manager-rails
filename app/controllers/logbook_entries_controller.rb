class LogbookEntriesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: %i[index show]
  before_action :set_entry, only: %i[show edit update destroy verify]
  before_action :require_unsigned, only: %i[edit update destroy]

  def index
    @query = params[:q]
    @log_type = params[:log_type].presence
    scope = @aircraft.logbook_entries.search(@query).recent_first.includes(:document, :signature)
    scope = scope.where(log_type: @log_type) if @log_type
    @unverified_only = params[:unverified] == "1"
    scope = scope.unverified if @unverified_only
    @unverified_count = @aircraft.logbook_entries.unverified.count
    @entries = scope.limit(500)
  end

  # Someone has checked a transcribed entry against the scan.
  def verify
    @entry.update!(verified: true)
    log_event("logbook", t("flash.logbook_entries.transcribed_logbook_entry_verified", date: @entry.date))
    next_entry = @aircraft.logbook_entries.unverified.order(:date, :id).first
    redirect_to next_entry ? aircraft_logbook_entry_path(@aircraft, next_entry) : aircraft_logbook_entries_path(@aircraft),
                notice: next_entry ? t("flash.logbook_entries.verified_next") : t("flash.logbook_entries.verified_all")
  end

  def show; end

  def new
    LogbookTemplate.ensure_defaults!
    @entry = (original = correctable(params[:supersedes])) ? correction_of(original) : @aircraft.logbook_entries.new(date: Date.current, aircraft_hours_at_entry: @aircraft.current_hours)
  end

  def create
    @entry = @aircraft.logbook_entries.new(entry_params)
    @entry.supersedes = correctable(params.dig(:logbook_entry, :supersedes_id))
    @entry.assign_parts(parts_params, @aircraft)
    if @entry.save
      log_event("logbook", t(@entry.supersedes ? "flash.logbook_entries.correction_added_event" : "flash.logbook_entries.logbook_entry_added", date: @entry.date))
      record_parts_service
      record_inspections
      redirect_to aircraft_logbook_entry_path(@aircraft, @entry),
                  notice: @entry.supersedes ? t("flash.logbook_entries.correction_saved") : t("flash.logbook_entries.added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @entry.assign_attributes(entry_params)
    @entry.assign_parts(parts_params, @aircraft)
    if @entry.save
      log_event("logbook", t("flash.logbook_entries.logbook_entry_updated_2", date: @entry.date))
      redirect_to aircraft_logbook_entry_path(@aircraft, @entry), notice: t("flash.logbook_entries.logbook_entry_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy!
    log_event("logbook", t("flash.logbook_entries.logbook_entry_deleted_2", date: @entry.date))
    redirect_to aircraft_logbook_entries_path(@aircraft), notice: t("flash.logbook_entries.logbook_entry_deleted")
  end

  private

  # Signed entries are locked (AC 120-78B 2.1.2.8): changes go in a correction.
  def require_unsigned
    return unless @entry.signed?
    redirect_to aircraft_logbook_entry_path(@aircraft, @entry), alert: t("flash.logbook_entries.this_entry_is_signed")
  end

  # A signed, not yet superseded entry of this aircraft.
  def correctable(id)
    return if id.blank?
    entry = @aircraft.logbook_entries.find_by(id: id)
    entry if entry&.signed? && !entry.superseded?
  end

  # A new entry starting from the signed one it corrects; signed afresh.
  def correction_of(original)
    copy = @aircraft.logbook_entries.new(original.attributes.slice(*%w[date log_type entry_type text aircraft_hours_at_entry signoff_location
                                                                         inspection_result component_id component_hours_at_entry
                                                                         component_since_overhaul_at_entry document_id page_number]))
    copy.supersedes = original
    original.parts.each { copy.parts.build(component_id: _1.component_id, hours_at_entry: _1.hours_at_entry, since_overhaul_at_entry: _1.since_overhaul_at_entry) }
    copy
  end

  # Sub-components marked "Serviced" or "Replaced" on a new entry: recorded on
  # the Components tab too, dated to the entry.
  def record_parts_service
    flown = (@aircraft.current_hours - @entry.aircraft_hours_at_entry if @entry.aircraft_hours_at_entry)
    parts_params.each do |id, p|
      next unless p["include"] == "1" && %w[serviced replaced].include?(p["service"])
      part = @entry.parts.find { _1.component_id == id.to_i } or next
      component = part.component
      component.service_from_entry!(date: @entry.date, hours_at_entry: part.hours_at_entry, flown_since: flown, replaced: p["service"] == "replaced")
      log_event("component", t(p["service"] == "replaced" ? "flash.logbook_entries.replaced_event" : "flash.logbook_entries.serviced_event", component: component, date: @entry.date))
    end
  end

  # Inspections ticked on a new entry (e.g. Oil Change): done at the entry's
  # date and airframe time, linked to it.
  def record_inspections
    ids = Array(params.dig(:logbook_entry, :inspection_type_ids)).compact_blank
    @aircraft.applicable_inspection_types.where(id: ids).find_each do |type|
      @aircraft.inspection_records.create!(inspection_type: type, logbook_entry: @entry, date: @entry.date,
                                           aircraft_hours: @entry.aircraft_hours_at_entry)
      log_event("inspection", t("flash.logbook_entries.inspection_completed_logbook_entry", name: type.name, date: @entry.date))
    end
  end

  # Sub-components ticked on the form: { component_id => { include, hours, since, service } }.
  def parts_params
    params.fetch(:logbook_entry, {}).permit(parts: {})[:parts]&.to_h || {}
  end

  def set_entry = @entry = @aircraft.logbook_entries.find(params[:id])

  def entry_params
    p = params.require(:logbook_entry).permit(:log_type, :entry_type, :date, :text, :signoff_person,
                                              :signoff_location, :aircraft_hours_at_entry, :document_id, :page_number,
                                              :signoff_certificate_type, :signoff_certificate_number, :inspection_result, :verified,
                                              :component_id, :component_hours_at_entry, :component_since_overhaul_at_entry)
    p[:document_id] = scoped_id(@aircraft.documents, p[:document_id])
    p[:component_id] = scoped_id(@aircraft.components, p[:component_id]) if p.key?(:component_id)
    p
  end
end

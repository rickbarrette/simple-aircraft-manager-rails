class LogbookEntriesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: %i[index show]
  before_action :set_entry, only: %i[show edit update destroy verify]

  def index
    @query = params[:q]
    @log_type = params[:log_type].presence
    scope = @aircraft.logbook_entries.search(@query).recent_first.includes(:document)
    scope = scope.where(log_type: @log_type) if @log_type
    @unverified_only = params[:unverified] == "1"
    scope = scope.unverified if @unverified_only
    @unverified_count = @aircraft.logbook_entries.unverified.count
    @entries = scope.limit(500)
  end

  # Someone has checked a transcribed entry against the scan.
  def verify
    @entry.update!(verified: true)
    log_event("logbook", "Transcribed logbook entry verified: #{@entry.date}")
    next_entry = @aircraft.logbook_entries.unverified.order(:date, :id).first
    redirect_to next_entry ? aircraft_logbook_entry_path(@aircraft, next_entry) : aircraft_logbook_entries_path(@aircraft),
                notice: next_entry ? "Verified. Here's the next one to check." : "Verified. All transcribed entries are checked."
  end

  def show; end

  def new
    @entry = @aircraft.logbook_entries.new(date: Date.current, aircraft_hours_at_entry: @aircraft.current_hours)
  end

  def create
    @entry = @aircraft.logbook_entries.new(entry_params)
    if @entry.save
      log_event("logbook", "Logbook entry added (#{@entry.date})")
      redirect_to aircraft_logbook_entries_path(@aircraft), notice: "Logbook entry added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @entry.update(entry_params)
      log_event("logbook", "Logbook entry updated (#{@entry.date})")
      redirect_to aircraft_logbook_entry_path(@aircraft, @entry), notice: "Logbook entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy!
    log_event("logbook", "Logbook entry deleted (#{@entry.date})")
    redirect_to aircraft_logbook_entries_path(@aircraft), notice: "Logbook entry deleted."
  end

  private

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

class LogbookEntriesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: %i[index show]
  before_action :set_entry, only: %i[show edit update destroy]

  def index
    @query = params[:q]
    @log_type = params[:log_type].presence
    scope = @aircraft.logbook_entries.search(@query).recent_first.includes(:document)
    scope = scope.where(log_type: @log_type) if @log_type
    @entries = scope.limit(500)
  end

  def show; end

  def new
    @entry = @aircraft.logbook_entries.new(date: Date.current, aircraft_hours_at_entry: @aircraft.tach_time)
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
                                              :signoff_location, :aircraft_hours_at_entry, :document_id, :page_number)
    p[:document_id] = scoped_id(@aircraft.documents, p[:document_id])
    p
  end
end

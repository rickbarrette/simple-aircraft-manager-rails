class MajorRecordsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: %i[index show]
  before_action :set_record, only: %i[show edit update destroy]

  def index
    @records = @aircraft.major_records.recent_first.includes(:component)
  end

  def show; end

  def new
    @record = @aircraft.major_records.new(record_type: params[:type] || "repair", date_performed: Date.current,
                                          aircraft_hours: @aircraft.current_hours)
  end

  def create
    @record = @aircraft.major_records.new(record_params)
    if @record.save
      log_event("major_record", t("flash.major_records.added", type_label: @record.type_label, title: @record.title))
      redirect_to aircraft_major_records_path(@aircraft), notice: t("flash.major_records.record_added")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @record.update(record_params)
      log_event("major_record", t("flash.major_records.updated", type_label: @record.type_label, title: @record.title))
      redirect_to aircraft_major_record_path(@aircraft, @record), notice: t("flash.major_records.record_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy!
    log_event("major_record", t("flash.major_records.deleted", type_label: @record.type_label, title: @record.title))
    redirect_to aircraft_major_records_path(@aircraft), notice: t("flash.major_records.record_deleted")
  end

  private

  def set_record = @record = @aircraft.major_records.find(params[:id])

  def record_params
    p = params.require(:major_record).permit(
      :record_type, :title, :description, :date_performed, :performed_by, :component_id,
      :form_337_document_id, :stc_number, :stc_holder, :stc_document_id, :logbook_entry_id,
      :aircraft_hours, :has_ica, :ica_notes, :notes
    )
    p[:component_id] = scoped_id(@aircraft.components, p[:component_id])
    p[:logbook_entry_id] = scoped_id(@aircraft.logbook_entries, p[:logbook_entry_id])
    %i[form_337_document_id stc_document_id].each { |k| p[k] = scoped_id(@aircraft.documents, p[k]) }
    p
  end
end

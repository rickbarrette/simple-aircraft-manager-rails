class InspectionRecordsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_record, only: %i[edit update destroy]

  def new
    @record = InspectionRecord.new(aircraft: @aircraft, date: Date.current,
                                   aircraft_hours: @aircraft.current_hours,
                                   inspection_type_id: params[:inspection_type_id])
  end

  def create
    @record = InspectionRecord.new(record_params.merge(aircraft: @aircraft))
    if @record.save
      log_event("inspection", t("flash.inspection_records.inspection_completed", name: @record.inspection_type.name))
      redirect_to aircraft_inspections_path(@aircraft), notice: t("flash.inspection_records.inspection_recorded")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @record.update(record_params)
      log_event("inspection", t("flash.inspection_records.inspection_record_updated_2", name: @record.inspection_type.name))
      redirect_to aircraft_inspections_path(@aircraft), notice: t("flash.inspection_records.inspection_record_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy!
    log_event("inspection", t("flash.inspection_records.inspection_record_deleted_2", name: @record.inspection_type.name))
    redirect_to aircraft_inspections_path(@aircraft), notice: t("flash.inspection_records.inspection_record_deleted")
  end

  private

  def set_record = @record = InspectionRecord.for_aircraft(@aircraft).find(params[:id])

  def record_params
    p = params.require(:inspection_record).permit(:inspection_type_id, :date, :aircraft_hours, :notes,
                                                  :logbook_entry_id, :component_id)
    p[:inspection_type_id] = scoped_id(@aircraft.applicable_inspection_types, p[:inspection_type_id])
    p[:logbook_entry_id] = scoped_id(@aircraft.logbook_entries, p[:logbook_entry_id])
    p[:component_id] = scoped_id(@aircraft.components, p[:component_id])
    p
  end
end

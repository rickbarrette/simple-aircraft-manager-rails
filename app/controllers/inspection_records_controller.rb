class InspectionRecordsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_record, only: %i[edit update destroy]

  def new
    @record = InspectionRecord.new(aircraft: @aircraft, date: Date.current,
                                   aircraft_hours: @aircraft.tach_time,
                                   inspection_type_id: params[:inspection_type_id])
  end

  def create
    @record = InspectionRecord.new(record_params.merge(aircraft: @aircraft))
    if @record.save
      log_event("inspection", "Inspection completed: #{@record.inspection_type.name}")
      redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @record.update(record_params)
      log_event("inspection", "Inspection record updated: #{@record.inspection_type.name}")
      redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection record updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy!
    log_event("inspection", "Inspection record deleted: #{@record.inspection_type.name}")
    redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection record deleted."
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

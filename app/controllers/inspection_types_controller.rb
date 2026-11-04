class InspectionTypesController < ApplicationController
  include AircraftScoped
  include Applicability
  before_action :require_owner!
  before_action :set_type, only: %i[edit update destroy]

  def new
    @inspection_type = InspectionType.new(required: true, recurring: true)
    @applies_to_airframe = true
  end

  def create
    @inspection_type = InspectionType.new(type_params)
    InspectionType.transaction do
      @inspection_type.save!
      apply_applicability(@inspection_type, to_airframe: applies_to_airframe?, component_ids: applicable_component_ids)
    end
    log_event("inspection", "Inspection type added: #{@inspection_type.name}")
    redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection type added."
  rescue ActiveRecord::RecordInvalid
    @applies_to_airframe = applies_to_airframe?
    render :new, status: :unprocessable_entity
  end

  def edit
    @applies_to_airframe = @inspection_type.aircraft.include?(@aircraft)
  end

  def update
    InspectionType.transaction do
      @inspection_type.update!(type_params)
      apply_applicability(@inspection_type, to_airframe: applies_to_airframe?, component_ids: applicable_component_ids)
    end
    log_event("inspection", "Inspection type updated: #{@inspection_type.name}")
    redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection type updated."
  rescue ActiveRecord::RecordInvalid
    @applies_to_airframe = applies_to_airframe?
    render :edit, status: :unprocessable_entity
  end

  def destroy
    detach_from_aircraft(@inspection_type)
    log_event("inspection", "Inspection type removed: #{@inspection_type.name}")
    redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection removed from #{@aircraft.tail_number}."
  end

  private

  def set_type
    @inspection_type = @aircraft.applicable_inspection_types.find(params[:id])
  end

  def type_params
    params.require(:inspection_type).permit(:name, :recurring, :required, :recurring_hours, :recurring_days, :recurring_months)
  end
end

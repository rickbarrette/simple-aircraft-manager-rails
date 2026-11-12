class InspectionTypesController < ApplicationController
  include AircraftScoped
  include Applicability
  before_action :require_owner!
  before_action :set_type, only: %i[edit update destroy]

  def new
    @inspection_type = InspectionType.new(required: true, recurring: true)
    @applies_to_airframe = true
    if (@major_record = ica_record)
      @inspection_type.name = "ICA: #{@major_record.title}".first(120)
      @applies_to_airframe = @major_record.component.nil?
      @inspection_type.components = [ @major_record.component ] if @major_record.component
    end
  end

  def create
    @inspection_type = InspectionType.new(type_params)
    InspectionType.transaction do
      @inspection_type.save!
      apply_applicability(@inspection_type, to_airframe: applies_to_airframe?, component_ids: applicable_component_ids)
      ica_record&.update!(ica_inspection_type: @inspection_type)
    end
    log_event("inspection", "Inspection type added: #{@inspection_type.name}")
    if (record = ica_record)
      redirect_to aircraft_major_record_path(@aircraft, record), notice: "ICA inspection added. Record when it was last done to see when it's next due."
    else
      redirect_to aircraft_inspections_path(@aircraft), notice: "Inspection type added."
    end
  rescue ActiveRecord::RecordInvalid
    @applies_to_airframe = applies_to_airframe?
    @major_record = ica_record
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

  # Creating the inspection an STC's ICA calls for (from its major record).
  def ica_record
    @aircraft.major_records.find_by(id: params[:major_record_id]) if params[:major_record_id].present?
  end

  def set_type
    @inspection_type = @aircraft.applicable_inspection_types.find(params[:id])
  end

  def type_params
    p = params.require(:inspection_type).permit(:name, :recurring, :effect, :hours_tolerance, :satisfies_id,
                                                :recurring_hours, :recurring_days, :recurring_months, :recurring_every, :recurring_unit)
    p[:satisfies_id] = scoped_id(@aircraft.applicable_inspection_types, p[:satisfies_id]) if p.key?(:satisfies_id)
    p
  end
end

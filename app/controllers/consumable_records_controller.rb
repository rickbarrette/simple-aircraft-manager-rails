class ConsumableRecordsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, only: %i[edit update destroy]
  before_action :set_record, only: %i[edit update destroy]

  RECORDS_PER_PAGE = 50

  # Records a page at a time; the rest load as you scroll (each page ends in
  # a lazy frame that fetches the next). The charts cover everything.
  def index
    @page = [ params[:page].to_i, 1 ].max
    rows = @aircraft.consumable_records.recent_first.offset((@page - 1) * RECORDS_PER_PAGE).limit(RECORDS_PER_PAGE + 1).to_a
    @more = rows.size > RECORDS_PER_PAGE
    @records = rows.first(RECORDS_PER_PAGE)
    return render(partial: "consumable_records/records", locals: { records: @records, page: @page, more: @more }) if turbo_frame_request?

    @oil = ConsumptionStats.new(@aircraft, "oil")
    @fuel = ConsumptionStats.new(@aircraft, "fuel")
  end

  def new
    type = params[:type].in?(ConsumableRecord::TYPES.keys) ? params[:type] : "oil"
    @record = @aircraft.consumable_records.new(record_type: type, date: Date.current,
                                               flight_hours: @aircraft.tach_time)
  end

  def create
    @record = @aircraft.consumable_records.new(record_params)
    if @record.save
      log_event(@record.record_type, "#{@record.record_type.capitalize} added: #{@record.quantity_added} #{@record.unit}")
      redirect_to aircraft_consumable_records_path(@aircraft), notice: "Record added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @record.update(record_params)
      log_event(@record.record_type, "#{@record.record_type.capitalize} record updated")
      redirect_to aircraft_consumable_records_path(@aircraft), notice: "Record updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy!
    log_event(@record.record_type, "#{@record.record_type.capitalize} record deleted")
    redirect_to aircraft_consumable_records_path(@aircraft), notice: "Record deleted."
  end

  private

  def set_record = @record = @aircraft.consumable_records.find(params[:id])

  def record_params
    params.require(:consumable_record).permit(:record_type, :date, :quantity_added, :level_after,
                                              :consumable_type, :flight_hours, :notes, :excluded_from_averages)
  end
end

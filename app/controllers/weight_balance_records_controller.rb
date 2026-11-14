# Weight & balance history and the loading calculator (pilots use it; owners
# keep the records and the loading setup).
class WeightBalanceRecordsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: :index
  before_action :set_record, only: %i[edit update destroy]

  def index
    @records = @aircraft.weight_balance_records.recent_first.includes(:major_record, :document)
    @current = @records.first
  end

  def new
    last = @aircraft.current_weight_balance
    @record = @aircraft.weight_balance_records.new(date: Date.current, max_gross_weight: last&.max_gross_weight,
                                                   major_record_id: params[:major_record_id])
  end

  def create
    @record = @aircraft.weight_balance_records.new(record_params)
    if @record.save
      log_event("aircraft", t("flash.weight_balance_records.weight_balance_recorded_lb", empty_weight: @record.empty_weight, empty_arm: @record.empty_arm))
      redirect_to aircraft_weight_balance_records_path(@aircraft), notice: t("flash.weight_balance_records.weight_balance_saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @record.update(record_params)
      log_event("aircraft", t("flash.weight_balance_records.weight_balance_updated_2", date: l(@record.date, format: :app)))
      redirect_to aircraft_weight_balance_records_path(@aircraft), notice: t("flash.weight_balance_records.weight_balance_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy!
    log_event("aircraft", t("flash.weight_balance_records.weight_balance_record_deleted", date: l(@record.date, format: :app)))
    redirect_to aircraft_weight_balance_records_path(@aircraft), notice: t("flash.weight_balance_records.record_deleted")
  end

  private

  def set_record = @record = @aircraft.weight_balance_records.find(params[:id])

  def record_params
    p = params.require(:weight_balance_record).permit(:date, :empty_weight, :empty_arm, :max_gross_weight, :reason, :notes,
                                                      :major_record_id, :document_id)
    p[:major_record_id] = scoped_id(@aircraft.major_records, p[:major_record_id])
    p[:document_id] = scoped_id(@aircraft.documents, p[:document_id])
    p
  end
end

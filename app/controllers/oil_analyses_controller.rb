class OilAnalysesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, only: %i[edit update destroy]
  before_action :set_analysis, only: %i[show edit update destroy]

  COMPARE_SAMPLES = 6 # columns in the trend table, like the lab report's history

  def index
    @analyses = @aircraft.oil_analyses.recent_first.includes(:component).with_attached_report
  end

  def show
    @previous = @aircraft.oil_analyses.where(component_id: @analysis.component_id)
                         .where("sample_date < ?", @analysis.sample_date).recent_first.first
  end

  def new
    engine = default_engine
    @analysis = @aircraft.oil_analyses.new(sample_date: Date.current, component: engine,
                                           engine_hours: engine&.hours_since_overhaul,
                                           lab: @aircraft.oil_analyses.recent_first.pick(:lab))
  end

  def create
    @analysis = @aircraft.oil_analyses.new(analysis_params)
    if @analysis.save
      log_event("oil_analysis", t("flash.oil_analyses.oil_analysis_added_sampled", sample_date: @analysis.sample_date))
      redirect_to aircraft_oil_analysis_path(@aircraft, @analysis), notice: t("flash.oil_analyses.oil_analysis_saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Create records from a lab report PDF (AvLab or Blackstone). Reports repeat
  # earlier samples, so samples already on file are skipped rather than duplicated.
  def import
    file = params[:report]
    return redirect_to(new_aircraft_oil_analysis_path(@aircraft), alert: t("flash.oil_analyses.choose_a_lab_report")) if file.blank?

    report = OilReportParser.from_pdf(file.tempfile)
    file.rewind
    if report.tail_number.present? && normalize_tail(report.tail_number) != normalize_tail(@aircraft.tail_number)
      return redirect_to(new_aircraft_oil_analysis_path(@aircraft),
                         alert: t("flash.oil_analyses.that_report_is_for", report_tail: report.tail_number, tail_number: @aircraft.tail_number))
    end

    engine = engine_for(report)
    created = []
    current_record = nil
    OilAnalysis.transaction do
      report.samples.each do |sample|
        record = existing_sample(sample) ||
                 @aircraft.oil_analyses.create!(sample.except(:current).merge(lab: report.lab, oil_type: report.oil_type, component: engine)).tap { created << _1 }
        current_record = record if sample[:current]
      end
    end
    current_record.report.attach(file) if current_record && !current_record.report.attached?

    skipped = report.samples.size - created.size
    created.each { log_event("oil_analysis", t("flash.oil_analyses.oil_analysis_imported_sampled", sample_date: _1.sample_date)) }
    notice = t("flash.oil_analyses.imported", count: created.size, lab: report.lab)
    notice += " #{t('flash.oil_analyses.already_recorded', count: skipped)}" if skipped.positive?
    redirect_to aircraft_oil_analyses_path(@aircraft), notice: notice
  rescue OilReportParser::Error => e
    redirect_to new_aircraft_oil_analysis_path(@aircraft), alert: t("flash.oil_analyses.couldn_t_import_that", message: e.message)
  end

  def edit; end

  def update
    if @analysis.update(analysis_params)
      log_event("oil_analysis", t("flash.oil_analyses.oil_analysis_updated_sampled", sample_date: @analysis.sample_date))
      redirect_to aircraft_oil_analysis_path(@aircraft, @analysis), notice: t("flash.oil_analyses.oil_analysis_updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @analysis.destroy!
    log_event("oil_analysis", t("flash.oil_analyses.oil_analysis_deleted_sampled", sample_date: @analysis.sample_date))
    redirect_to aircraft_oil_analyses_path(@aircraft), notice: t("flash.oil_analyses.oil_analysis_deleted")
  end

  private

  def set_analysis = @analysis = @aircraft.oil_analyses.find(params[:id])

  def normalize_tail(tail) = tail.to_s.upcase.delete("^A-Z0-9")

  # Same sample date, and the same lab sample number unless one side has none.
  def existing_sample(sample)
    scope = @aircraft.oil_analyses.where(sample_date: sample[:sample_date])
    scope = scope.where(sample_number: [ sample[:sample_number], nil ]) if sample[:sample_number]
    scope.first
  end

  # The engine whose serial number is on the report, else the one in service.
  def engine_for(report)
    serial = report.engine_serial.to_s.strip.upcase
    match = @aircraft.components.where.not(serial_number: [ nil, "" ]).find { _1.serial_number.strip.upcase == serial } if serial.present?
    match || default_engine
  end

  def default_engine
    @aircraft.components.joins(:component_type).where(status: "IN-USE", component_types: { name: "Engine" }).first
  end

  def analysis_params
    params.require(:oil_analysis).permit(
      :component_id, :sample_date, :analysis_date, :lab, :sample_number, :oil_type, :engine_hours, :oil_hours,
      :filter_hours, :oil_added, :status, :lab_comments, :notes, :report, :excluded_from_averages,
      elements: OilAnalysis::ELEMENTS.keys, element_averages: OilAnalysis::ELEMENTS.keys,
      oil_properties: OilAnalysis::PROPERTIES.keys
    ).tap { |p| p[:component_id] = scoped_id(@aircraft.components, p[:component_id]) if p.key?(:component_id) }
  end
end

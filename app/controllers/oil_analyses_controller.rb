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
      log_event("oil_analysis", "Oil analysis added (sampled #{@analysis.sample_date})")
      redirect_to aircraft_oil_analysis_path(@aircraft, @analysis), notice: "Oil analysis saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Create records from a lab report PDF. AvLab reports include the two previous
  # samples too, so samples already on file are skipped rather than duplicated.
  def import
    file = params[:report]
    return redirect_to(new_aircraft_oil_analysis_path(@aircraft), alert: "Choose a lab report PDF.") if file.blank?

    report = OilReportParser.from_pdf(file.tempfile)
    file.rewind
    if report.tail_number.present? && normalize_tail(report.tail_number) != normalize_tail(@aircraft.tail_number)
      return redirect_to(new_aircraft_oil_analysis_path(@aircraft),
                         alert: "That report is for #{report.tail_number}, not #{@aircraft.tail_number}.")
    end

    engine = engine_for(report)
    created = []
    current_record = nil
    OilAnalysis.transaction do
      report.samples.each do |sample|
        record = existing_sample(sample) ||
                 @aircraft.oil_analyses.create!(sample.except(:current).merge(lab: report.lab, component: engine)).tap { created << _1 }
        current_record = record if sample[:current]
      end
    end
    current_record.report.attach(file) if current_record && !current_record.report.attached?

    skipped = report.samples.size - created.size
    created.each { log_event("oil_analysis", "Oil analysis imported (sampled #{_1.sample_date})") }
    notice = "Imported #{helpers.pluralize(created.size, 'sample')} from the #{report.lab} report."
    notice += " #{helpers.pluralize(skipped, 'sample was', plural: 'samples were')} already recorded." if skipped.positive?
    redirect_to aircraft_oil_analyses_path(@aircraft), notice: notice
  rescue OilReportParser::Error => e
    redirect_to new_aircraft_oil_analysis_path(@aircraft), alert: "Couldn't import that report: #{e.message}"
  end

  def edit; end

  def update
    if @analysis.update(analysis_params)
      log_event("oil_analysis", "Oil analysis updated (sampled #{@analysis.sample_date})")
      redirect_to aircraft_oil_analysis_path(@aircraft, @analysis), notice: "Oil analysis updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @analysis.destroy!
    log_event("oil_analysis", "Oil analysis deleted (sampled #{@analysis.sample_date})")
    redirect_to aircraft_oil_analyses_path(@aircraft), notice: "Oil analysis deleted."
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
      :component_id, :sample_date, :analysis_date, :lab, :sample_number, :engine_hours, :oil_hours,
      :filter_hours, :oil_added, :status, :lab_comments, :notes, :report,
      *OilAnalysis::ELEMENTS.keys.flat_map { [ _1, :"#{_1}_avg" ] }
    ).tap { |p| p[:component_id] = scoped_id(@aircraft.components, p[:component_id]) if p.key?(:component_id) }
  end
end

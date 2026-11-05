class AdCompliancesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_compliance, only: %i[edit update destroy]

  def new
    ad = @aircraft.applicable_ads.find_by(id: params[:ad_id])
    @compliance = AdCompliance.new(aircraft: @aircraft, airworthiness_directive: ad, date_complied: Date.current,
                                   aircraft_hours_at_compliance: @aircraft.tach_time,
                                   not_applicable: params[:not_applicable] == "1")
    @compliance.compliance_notes = "Not applicable: " if @compliance.not_applicable?
    @compliance.fill_next_due
  end

  def create
    @compliance = AdCompliance.new(compliance_params.merge(aircraft: @aircraft))
    if @compliance.save
      log_event("ad", "#{@compliance.not_applicable? ? "Marked N/A" : "Compliance recorded"}: #{@compliance.airworthiness_directive.name}")
      redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "Compliance recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @compliance.update(compliance_params)
      log_event("ad", "Compliance updated: #{@compliance.airworthiness_directive.name}")
      redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "Compliance updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @compliance.destroy!
    log_event("ad", "Compliance deleted: #{@compliance.airworthiness_directive.name}")
    redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "Compliance record deleted."
  end

  private

  def set_compliance = @compliance = AdCompliance.for_aircraft(@aircraft).find(params[:id])

  def compliance_params
    p = params.require(:ad_compliance).permit(
      :airworthiness_directive_id, :date_complied, :compliance_notes, :permanent, :next_due_at_time,
      :aircraft_hours_at_compliance, :logbook_entry_id, :inspection_record_id, :component_id, :not_applicable
    )
    p[:airworthiness_directive_id] = scoped_id(@aircraft.applicable_ads, p[:airworthiness_directive_id])
    p[:logbook_entry_id] = scoped_id(@aircraft.logbook_entries, p[:logbook_entry_id])
    p[:inspection_record_id] = scoped_id(InspectionRecord.for_aircraft(@aircraft), p[:inspection_record_id])
    p[:component_id] = scoped_id(@aircraft.components, p[:component_id])
    p
  end
end

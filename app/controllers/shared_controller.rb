# Read-only public view of an aircraft via a share link — no login required.
# 'status' links see current state; 'maintenance' links also see full history.
class SharedController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :redirect_to_setup
  layout "public"

  # The maintenance status report, for "Maintenance Detail" links (mechanics,
  # inspectors, buyers).
  def report
    @share = ShareToken.find_active(params[:token]) or raise ActiveRecord::RecordNotFound
    raise ActiveRecord::RecordNotFound unless @share.maintenance?
    @report = MaintenanceReport.new(@share.aircraft)
    render "maintenance_reports/show", layout: "report"
  end

  def show
    @share = ShareToken.find_active(params[:token]) or raise ActiveRecord::RecordNotFound
    @aircraft = @share.aircraft
    @airworthiness = @aircraft.airworthiness
    @components = @aircraft.components.where.not(status: "DISPOSED").includes(:component_type).order(:install_location)
    @active_squawks = @aircraft.squawks.active.by_priority
    @notes = @aircraft.notes.visible_publicly.recent_first
    @ad_rows = Compliance.ad_rows(@aircraft)
    @inspection_rows = Compliance.inspection_rows(@aircraft)
    @oil = ConsumptionStats.new(@aircraft, "oil")
    @fuel = ConsumptionStats.new(@aircraft, "fuel")
    @documents = @aircraft.documents.includes(:document_collection, pages_attachments: :blob)
                          .select { |d| d.visible_to_share?(@share) }

    if @share.maintenance?
      @logbook = @aircraft.logbook_entries.recent_first
      @resolved_squawks = @aircraft.squawks.resolved.order(resolved_at: :desc)
      @major_records = @aircraft.major_records.recent_first
      @inspection_history = InspectionRecord.for_aircraft(@aircraft).recent_first.includes(:inspection_type)
      @ad_history = AdCompliance.for_aircraft(@aircraft).recent_first.includes(:airworthiness_directive)
    end
  end
end

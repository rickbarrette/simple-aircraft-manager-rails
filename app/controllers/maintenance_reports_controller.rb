# Printable maintenance status report (Print / Save as PDF in the browser).
class MaintenanceReportsController < ApplicationController
  include AircraftScoped

  def show
    @report = MaintenanceReport.new(@aircraft)
    log_event("aircraft", t("flash.maintenance_reports.maintenance_status_report_viewed")) if params[:print]
    render layout: "report"
  end
end

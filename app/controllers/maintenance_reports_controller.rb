# Printable maintenance status report (Print / Save as PDF in the browser).
class MaintenanceReportsController < ApplicationController
  include AircraftScoped

  def show
    @report = MaintenanceReport.new(@aircraft)
    log_event("aircraft", "Maintenance status report viewed") if params[:print]
    render layout: "report"
  end
end

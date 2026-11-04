class InspectionsController < ApplicationController
  include AircraftScoped

  def index
    @rows = Compliance.inspection_rows(@aircraft)
    @history = InspectionRecord.for_aircraft(@aircraft).recent_first.includes(:inspection_type, :component, :logbook_entry)
  end
end

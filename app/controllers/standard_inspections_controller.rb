class StandardInspectionsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def new; end

  def create
    added = StandardInspections.add!(@aircraft, params[:templates])
    if added.any?
      log_event("inspection", "Standard inspections added", notes: added.map(&:name).join(", "))
      redirect_to aircraft_inspections_path(@aircraft), notice: "Added #{added.map(&:name).to_sentence}. Record when each was last done to see when it's next due."
    else
      redirect_to new_aircraft_standard_inspections_path(@aircraft), alert: "Nothing new was chosen."
    end
  end
end

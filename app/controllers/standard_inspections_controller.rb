class StandardInspectionsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def new; end

  def create
    added = StandardInspections.add!(@aircraft, params[:templates])
    if added.any?
      log_event("inspection", t("flash.standard_inspections.standard_inspections_added"), notes: added.map(&:name).join(", "))
      redirect_to aircraft_inspections_path(@aircraft), notice: t("flash.standard_inspections.added_record_when_each", items: added.map(&:name).to_sentence)
    else
      redirect_to new_aircraft_standard_inspections_path(@aircraft), alert: t("flash.standard_inspections.nothing_new_was_chosen")
    end
  end
end

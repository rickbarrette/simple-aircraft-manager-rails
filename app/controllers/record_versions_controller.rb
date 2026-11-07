# Every change to the aircraft's maintenance records (AC 120-78B 3.2.2).
class RecordVersionsController < ApplicationController
  include AircraftScoped

  def index
    @type = params[:type].presence_in(RecordVersion.where(aircraft_id: @aircraft.id).distinct.pluck(:item_type))
    scope = RecordVersion.where(aircraft_id: @aircraft.id).order(id: :desc).includes(:user)
    scope = scope.where(item_type: @type) if @type
    @versions = scope.limit(500)
    @types = RecordVersion.where(aircraft_id: @aircraft.id).distinct.pluck(:item_type).sort
  end
end

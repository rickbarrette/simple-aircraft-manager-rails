class AirportsController < ApplicationController
  # GET /airports/search?q=quonset → [{ code, name, place, airtrail_code, kind }]
  def search
    render json: Airport.search(params[:q], prefer: familiar_codes).map(&:as_suggestion)
  end

  private

  # Airports this aircraft has flown from/to rank first.
  def familiar_codes
    aircraft = params[:aircraft_id].presence && current_user.accessible_aircraft.find_by(id: params[:aircraft_id])
    return [] unless aircraft
    aircraft.flight_logs.distinct.pluck(:departure_location, :destination_location).flatten.compact_blank.uniq
  end
end

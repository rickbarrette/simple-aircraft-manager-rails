# One search box across the records of the aircraft the user can see
# (or one aircraft, from its own pages).
class SearchesController < ApplicationController
  rate_limit to: 60, within: 1.minute, with: -> { redirect_to root_path, alert: t("flash.searches.too_many_searches_wait") }

  def show
    fleet = current_user.accessible_aircraft.ordered.to_a
    @aircraft = fleet.find { _1.id == params[:aircraft_id].to_i } if params[:aircraft_id].present?
    @fleet = fleet
    @search = SiteSearch.new(params[:q], @aircraft || fleet)
  end
end

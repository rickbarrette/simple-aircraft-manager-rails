class EventsController < ApplicationController
  include AircraftScoped

  def index
    @category = params[:category].presence_in(AircraftEvent::CATEGORIES.keys)
    scope = @aircraft.events.includes(:user)
    scope = scope.where(category: @category) if @category
    @events = scope.limit(200)
  end
end

class EventsController < ApplicationController
  include AircraftScoped

  EVENTS_PER_PAGE = 50

  # A page at a time; the rest load as you scroll (each page ends in a lazy
  # frame that fetches the next).
  def index
    @category = params[:category].presence_in(AircraftEvent::CATEGORIES.keys)
    @page = [ params[:page].to_i, 1 ].max
    scope = @aircraft.events.includes(:user).reorder(created_at: :desc, id: :desc)
    scope = scope.where(category: @category) if @category
    rows = scope.offset((@page - 1) * EVENTS_PER_PAGE).limit(EVENTS_PER_PAGE + 1).to_a
    @more = rows.size > EVENTS_PER_PAGE
    @events = rows.first(EVENTS_PER_PAGE)
    render(partial: "events/page", locals: { events: @events, page: @page, more: @more, category: @category }) if turbo_frame_request?
  end
end

# The installed app's home-screen shortcuts (Log Flight, Report Squawk): the
# form for your aircraft, or a list to choose from when you have several.
class ShortcutsController < ApplicationController
  def log_flight = go(:log_flight, ->(a) { new_aircraft_flight_log_path(a) })
  def report_squawk = go(:report_squawk, ->(a) { new_aircraft_squawk_path(a) })

  private

  def go(action, path)
    aircraft = current_user.accessible_aircraft.ordered.to_a
    return redirect_to(path.(aircraft.first)) if aircraft.one?
    @title = t("shortcuts.choose.#{action}")
    @choices = aircraft.map { [ _1, path.(_1) ] }
    render :choose
  end
end

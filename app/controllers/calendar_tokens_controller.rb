# Profile: create (or replace) the secret calendar feed link.
class CalendarTokensController < ApplicationController
  def create
    current_user.regenerate_calendar_token
    redirect_to edit_profile_path(anchor: "calendar"), notice: "Calendar link ready. Any earlier link no longer works."
  end
end

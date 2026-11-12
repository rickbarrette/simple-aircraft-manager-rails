# The calendar feed: what's coming due on every aircraft the user can see,
# as all-day events (dates for hour-based items are projected from the past
# year's flying). Calendar apps fetch it with the secret link from Profile.
class CalendarFeedsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :redirect_to_setup
  rate_limit to: 60, within: 1.hour, with: -> { head :too_many_requests }

  def show
    user = User.active.find_by(calendar_token: params[:token].to_s) or return head(:not_found)
    cal = Ical.new("Aircraft maintenance")
    host = Sso.app_url
    user.accessible_aircraft.ordered.each do |aircraft|
      DueList.new(aircraft).items.each do |i|
        when_text = [ ("projected from recent flying" if i.projected), ("at #{i.due_hours} hrs" if i.due_hours) ].compact.join(", ")
        cal.add(uid: "#{aircraft.id}-#{i.key}@simple-aircraft-manager", date: i.date,
                summary: "#{aircraft.tail_number}: #{i.title}#{' (overdue)' if i.overdue?}",
                description: [ "#{aircraft.tail_number}: #{i.title}", when_text.presence ].compact.join("\n"), url: "#{host}#{i.path}")
      end
    end
    send_data cal.to_s, type: "text/calendar; charset=utf-8", disposition: "inline", filename: "aircraft-maintenance.ics"
  end
end

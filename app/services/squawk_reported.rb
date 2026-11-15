# What happens when a squawk is reported, from the form or the API: the
# aircraft's activity log, and a push notification to its other people when
# it grounds the aircraft.
module SquawkReported
  module_function

  def call(squawk, by:)
    aircraft = squawk.aircraft
    aircraft.log_event!("squawk", I18n.t("flash.squawks.squawk_reported_2", priority_label: squawk.priority_label),
                        user: by, notes: squawk.issue_reported.truncate(200))
    return unless squawk.grounding?
    PushNotifier.notify(aircraft.users.merge(User.active).where.not(id: by&.id), :grounding_squawk,
                        path: Rails.application.routes.url_helpers.aircraft_squawks_path(aircraft),
                        tag: "squawk-#{squawk.id}", tail: aircraft.tail_number, issue: squawk.issue_reported.truncate(120))
  end
end

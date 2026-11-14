# Each request runs in the viewer's time zone: the one chosen in Profile, else
# the device's (a "tz" cookie the page sets from the browser), else the
# installation's default (TZ). That decides how times show and
# what "today" is (e.g. a new flight's date). Signatures, the record history
# and exports keep exact UTC timestamps.
module TimeZones
  extend ActiveSupport::Concern

  included do
    around_action :use_time_zone
    helper_method :device_time_zone, :device_time_zone_label
  end

  private

  def use_time_zone(&)
    Time.use_zone(Current.user&.time_zone.presence || device_time_zone || Time.zone_default, &)
  end

  # "(GMT-08:00) Pacific Time (US & Canada)" for America/Los_Angeles.
  def device_time_zone_label
    return unless (zone = ActiveSupport::TimeZone[device_time_zone.to_s])
    (ActiveSupport::TimeZone.all.find { _1.tzinfo.identifier == zone.tzinfo.identifier } || zone).to_s
  end

  # The browser's zone, when it's one we know.
  def device_time_zone
    name = cookies[:tz].to_s.first(64)
    ActiveSupport::TimeZone[name] && name if name.present?
  end
end

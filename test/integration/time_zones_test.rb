require "test_helper"

# Times show in the viewer's zone (Profile, else their device, else the
# installation default), and "today" is their local date.
class TimeZonesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user("pilot@example.com")
    @a = create_aircraft(pilot: @user)
  end

  # 02:00 UTC on Nov 15 is still Nov 14 in the US.
  def at_night_utc(&) = travel_to(Time.utc(2026, 11, 15, 2, 0), &)

  def new_flight_date
    get new_aircraft_flight_log_path(@a)
    css_select("input[name='flight_log[date]']").first["value"]
  end

  test "a zone chosen in Profile sets today's date and how times show" do
    @user.update!(time_zone: "Eastern Time (US & Canada)")
    at_night_utc do
      sign_in @user
      assert_equal "2026-11-14", new_flight_date
      get edit_profile_path
      assert_select "select[name='user[time_zone]'] option[selected][value='Eastern Time (US & Canada)']"
      assert_match "Nov 14, 2026 21:00", response.body # the profile's "Now:"
    end
  end

  test "without a choice, the device's zone is used; without that, the default" do
    at_night_utc do
      sign_in @user
      assert_equal "2026-11-15", new_flight_date # UTC: device not known yet
      cookies[:tz] = "America/Los_Angeles"
      assert_equal "2026-11-14", new_flight_date
      get edit_profile_path
      assert_select "select[name='user[time_zone]'] option[value='']", /Automatic: this device \(.*Pacific/
      cookies[:tz] = "Not/AZone"
      assert_equal "2026-11-15", new_flight_date # unknown names are ignored
    end
  end

  test "the time zone is saved from Profile, and unknown ones are refused" do
    sign_in @user
    patch profile_path, params: { user: { time_zone: "Alaska" } }
    assert_equal "Alaska", @user.reload.time_zone
    patch profile_path, params: { user: { time_zone: "Mars/Olympus" } }
    assert_equal "Alaska", @user.reload.time_zone
    patch profile_path, params: { user: { time_zone: "" } }
    assert_nil @user.reload.time_zone # back to automatic
  end

  test "the weekly email works out dates in the recipient's zone" do
    @user.update!(time_zone: "Hawaii")
    zone = nil
    original = ReminderMailer.method(:items_for)
    ReminderMailer.define_singleton_method(:items_for) { |_| (zone = Time.zone.name) && [] }
    at_night_utc { ReminderMailer.weekly(@user).message }
    assert_equal "Hawaii", zone
  ensure
    ReminderMailer.define_singleton_method(:items_for, original) if original
  end
end

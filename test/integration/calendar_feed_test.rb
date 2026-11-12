require "test_helper"

# Calendar feed of what's coming due, with projected dates for hour-based items.
class CalendarFeedTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345", tach_time: 1000)
    # 36.5 hours flown in the past year: 0.1 hour a day
    @a.flight_logs.create!(date: Date.current - 100, tach_time: 36.5)
    @oil = create_component(@a, component_type: component_type("Oil"), manufacturer: "Phillips", model: "20W50",
                                replacement_hours: 50, replacement_days: 120, hours_since_overhaul: 45, overhaul_date: Date.current - 30)
    @mag = create_component(@a, component_type: component_type("Magneto"), manufacturer: "Bendix", model: "S4LN-21",
                                inspection_hours: 500, hours_since_overhaul: 450, overhaul_date: Date.current - 400)
    @a.documents.create!(name: "Registration", doc_type: "REGISTRATION", expires_on: Date.current + 200)
  end

  test "the due list dates calendar items and projects hour-based ones" do
    items = DueList.new(@a).items.index_by(&:key)
    oil = items["replace-#{@oil.id}"]
    assert_equal Date.current + 50, oil.date # 5 hrs at 0.1/day, before the 120-day limit (90 days left)
    assert oil.projected
    assert_equal 1005.0, oil.due_hours.to_f
    assert_equal Date.current + 500, items["inspect-#{@mag.id}"].date # 50 hrs / 0.1 a day
    assert_equal Date.current + 200, items["document-#{@a.documents.first.id}"].date
    refute items["document-#{@a.documents.first.id}"].projected
  end

  test "the profile makes a secret link; the feed is iCalendar without signing in; a new link retires the old" do
    @owner.update_column(:calendar_token, nil) # an account from before calendar links
    sign_in @owner
    get edit_profile_path
    assert_select "button", text: "Create calendar link"
    post calendar_token_path
    token = @owner.reload.calendar_token
    assert_equal 32, token.size
    get edit_profile_path
    assert_select "input[value*='/calendar/#{token}.ics']"
    assert_select "a[href^='webcal://']", text: "Subscribe"

    delete session_path
    get calendar_feed_path(token)
    assert_response :success
    assert_equal "text/calendar", response.media_type
    body = response.body
    unfolded = body.gsub("\r\n ", "")
    assert body.start_with?("BEGIN:VCALENDAR\r\n")
    assert_includes body, "SUMMARY:N12345: Replace Oil 20W50"
    assert_includes body, "DTSTART;VALUE=DATE:#{(Date.current + 50).strftime('%Y%m%d')}"
    assert_includes unfolded, "projected from recent flying\\, at 1005.0 hrs"
    assert body.lines.all? { _1.chomp.bytesize <= 75 } # folded

    sign_in @owner
    post calendar_token_path
    get calendar_feed_path(token)
    assert_response :not_found
    @owner.reload.update!(disabled_at: Time.current)
    get calendar_feed_path(@owner.calendar_token)
    assert_response :not_found
  end
end

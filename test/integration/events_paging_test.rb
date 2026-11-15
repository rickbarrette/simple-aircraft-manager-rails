require "test_helper"

# The activity log loads a page at a time (no more hidden events past 200).
class EventsPagingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    per = EventsController::EVENTS_PER_PAGE
    (per + 7).times do |i|
      @a.events.create!(category: i.even? ? "note" : "oil", event_name: "Event #{i}", created_at: Time.zone.local(2026, 1, 1) + i.hours)
    end
  end

  test "the first page has a page of events; the next page comes in a lazy frame" do
    sign_in @owner
    get aircraft_events_path(@a)
    assert_select "turbo-frame#events-1[target=_top] li", EventsController::EVENTS_PER_PAGE
    assert_select "turbo-frame#events-2[loading=lazy][src=?]", aircraft_events_path(@a, page: 2)

    get aircraft_events_path(@a, page: 2), headers: { "Turbo-Frame" => "events-2" }
    assert_select "turbo-frame#events-2 li", 7
    assert_select "turbo-frame#events-3", 0
    assert_select "h2", 0
    assert_includes response.body, "Event 0" # the oldest event is reachable
  end

  test "the next page keeps the category filter" do
    sign_in @owner
    get aircraft_events_path(@a, category: "note")
    assert_select "turbo-frame#events-1 li", 29
    assert_select "turbo-frame#events-2", 0
  end
end

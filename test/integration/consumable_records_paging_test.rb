require "test_helper"

# Oil & Fuel records load a page at a time (no more hidden records past 200).
class ConsumableRecordsPagingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    per = ConsumableRecordsController::RECORDS_PER_PAGE
    (per + 7).times do |i|
      @a.consumable_records.create!(record_type: i.even? ? "fuel" : "oil", date: Date.new(2026, 1, 1) + i, quantity_added: 1 + i, flight_hours: 1000 + i)
    end
  end

  test "the first page has the charts and a page of records; the next page comes in a lazy frame" do
    sign_in @owner
    get aircraft_consumable_records_path(@a)
    assert_select "tr.consumable-record", ConsumableRecordsController::RECORDS_PER_PAGE
    assert_select "turbo-frame#consumable-records-1[target=_top]"
    assert_select "turbo-frame#consumable-records-2[loading=lazy][src=?]", aircraft_consumable_records_path(@a, page: 2)
    assert_select "h2", text: "Fuel Burn"

    get aircraft_consumable_records_path(@a, page: 2), headers: { "Turbo-Frame" => "consumable-records-2" }
    assert_select "turbo-frame#consumable-records-2 tr.consumable-record", 7
    assert_select "turbo-frame#consumable-records-3", 0
    assert_select "thead", 0 # header only on the first page
    assert_select "h2", text: "Fuel Burn", count: 0
    assert_includes response.body, "Jan 1, 2026" # the oldest record is reachable
  end
end

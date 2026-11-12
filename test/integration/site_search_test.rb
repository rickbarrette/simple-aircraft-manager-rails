require "test_helper"

# One search box across the records of the aircraft you can see.
class SiteSearchTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    @other = create_aircraft(tail_number: "N99999") # not the owner's
    @mag = create_component(@a, component_type: component_type("Magneto"), manufacturer: "Bendix", model: "S4LN-21", serial_number: "10000000")
    @a.logbook_entries.create!(date: Date.new(2026, 5, 1), entry_type: "MAINTENANCE", text: "Inspected left magneto timing, set to 22° BTC.", aircraft_hours_at_entry: 1000)
    @a.squawks.create!(issue_reported: "Magneto drop 150 rpm on left", priority: 1)
    @a.documents.create!(name: "Magneto 500-hour inspection invoice", doc_type: "INVOICE")
    ad = AirworthinessDirective.create!(name: "2005-12-06", short_description: "Bendix magnetos impulse coupling")
    ad.components << @mag
    @other.squawks.create!(issue_reported: "Magneto on someone else's plane", priority: 1)
    sign_in @owner
  end

  test "finds matches in every kind of record, with the text around them, only on your aircraft" do
    get search_path(q: "magneto")
    assert_response :success
    %w[Logbook Squawks ADs Documents Components].each { |kind| assert_select "h2", text: /#{kind}/ }
    assert_select "mark", text: /magneto/i
    assert_includes response.body, "Inspected left <mark"
    refute_includes response.body, "someone else" # another owner's aircraft
    assert_select "a[href='#{aircraft_component_path(@a, @mag)}']"

    get search_path(q: "10000000") # serial number
    assert_select "h2", text: /Components/
    get search_path(q: "x")
    assert_includes response.body, "at least two characters"
    get search_path(q: "100%") # LIKE wildcards are literal
    assert_includes response.body, "0 results"
  end

  test "the top bar has the search box" do
    get root_path
    assert_select "form[action='#{search_path}'][role=search] input[name=q]"
  end
end

require "test_helper"

class AirTrailExportFlowTest < ActionDispatch::IntegrationTest
  setup do
    @pilot = create_user("jane@example.com")
    @a = create_aircraft(pilot: @pilot, owner: create_user, tail_number: "N12345")
    @a.flight_logs.create!(date: Date.current, departure_location: "KOQU", destination_location: "KBID", tach_time: 0.5)
    sign_in @pilot
  end

  test "pilot downloads the AirTrail file" do
    get aircraft_flight_logs_path(@a)
    assert_select "a[href='#{new_aircraft_air_trail_export_path(@a)}']", text: "Export for AirTrail"
    get new_aircraft_air_trail_export_path(@a)
    assert_response :success
    assert_select "input[name='username'][value='jane']"
    assert_select "form[data-turbo='false']"

    post aircraft_air_trail_export_path(@a), params: { username: "jane", aircraft_type: "C150", scope: "all" }
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment; filename="n12345-airtrail-.*\.json"/, response.headers["Content-Disposition"])
    assert_equal "KBID", JSON.parse(response.body)["flights"].first["to"]["code"]
  end

  test "invalid username re-renders the form" do
    post aircraft_air_trail_export_path(@a), params: { username: "x" }
    assert_response :unprocessable_entity
    assert_match "3–20 letters", response.body
  end
end

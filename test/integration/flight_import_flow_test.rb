require "test_helper"

class FlightImportFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @aircraft = create_aircraft(owner: @owner, pilot: @pilot, tach_time: 7270)
  end

  test "owner uploads, previews, and confirms" do
    sign_in @owner
    get new_aircraft_flight_import_path(@aircraft)
    assert_response :success

    post aircraft_flight_import_path(@aircraft), params: { file: fixture_file_upload("flights.csv", "text/csv") }
    # Turbo ignores a 200 render after a form POST, so upload must redirect to the preview
    assert_response :redirect
    assert_match %r{/flight_import\?}, response.location
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Tach went backwards"
    assert_includes response.body, "Import 12 Flights"
    token = response.body[/name="token"[^>]*value="([^"]+)"/, 1]
    assert token

    post confirm_aircraft_flight_import_path(@aircraft), params: { token: token, filename: "flights.csv", update_aircraft_hours: "1" }
    assert_redirected_to aircraft_flight_logs_path(@aircraft)
    assert_equal 12, @aircraft.flight_logs.count
    assert_equal BigDecimal("7290.3"), @aircraft.reload.tach_time

    # token is single-use
    post confirm_aircraft_flight_import_path(@aircraft), params: { token: token, filename: "flights.csv" }
    assert_redirected_to new_aircraft_flight_import_path(@aircraft)
    assert_equal 12, @aircraft.flight_logs.count
  end

  test "rejects path traversal tokens and wrong file types" do
    sign_in @owner
    post confirm_aircraft_flight_import_path(@aircraft), params: { token: "../../config/master.key", filename: "x.csv" }
    assert_redirected_to new_aircraft_flight_import_path(@aircraft)
    post aircraft_flight_import_path(@aircraft), params: { file: fixture_file_upload("flights.csv", "text/plain") .tap { |f| def f.original_filename = "evil.rb" } }
    assert_redirected_to new_aircraft_flight_import_path(@aircraft)
  end

  test "preview with a bogus token sends you back to upload" do
    sign_in @owner
    get aircraft_flight_import_path(@aircraft, token: "nope.csv")
    assert_redirected_to new_aircraft_flight_import_path(@aircraft)
  end

  test "pilots cannot import" do
    sign_in @pilot
    post aircraft_flight_import_path(@aircraft), params: { file: fixture_file_upload("flights.csv", "text/csv") }
    assert_response :redirect
    assert_equal 0, @aircraft.flight_logs.count
  end
end

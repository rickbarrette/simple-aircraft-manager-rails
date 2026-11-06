require "test_helper"

class EngineDataFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @other_pilot = create_user
    @aircraft = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345", tach_time: 7149.7)
    @aircraft.roles.create!(user: @other_pilot, role: "pilot")
  end

  def upload(name = "cgr30p.csv") = fixture_file_upload("engine_data/#{name}", "text/csv")

  test "pilot logs a flight with engine data and sees the summary and charts" do
    sign_in @pilot
    post aircraft_flight_logs_path(@aircraft), params: { flight_log: { date: "2025-07-14", tach_out: 7149.7, tach_in: 7149.8, engine_data: upload } }
    flight = @aircraft.flight_logs.last
    assert flight.engine_data.attached?

    get aircraft_flight_logs_path(@aircraft)
    assert_includes response.body, "Engine data attached"

    get aircraft_flight_log_path(@aircraft, flight)
    assert_response :success
    assert_includes response.body, "8m 39s"
    assert_includes response.body, "7149.77 → 7149.81 (0.04)"
    assert_includes response.body, "EGT (cyl 4)"
    assert_includes response.body, "No (ground run)"
    assert_includes response.body, "Chartkick"
    refute_includes response.body, "This recording is from"
  end

  test "an unreadable file is rejected when logging" do
    sign_in @pilot
    post aircraft_flight_logs_path(@aircraft), params: { flight_log: { date: "2025-07-14", tach_time: 0.1,
                                                                      engine_data: fixture_file_upload("flights.csv", "text/csv") } }
    assert_response :unprocessable_entity
    assert_includes response.body, "Not a recognized engine monitor file"
    assert_equal 0, @aircraft.flight_logs.count
  end

  test "attach to and remove from an existing flight; only owners or the flight's pilot" do
    flight = @aircraft.flight_logs.create!(date: Date.current, tach_time: 0.1, user: @pilot)

    sign_in @other_pilot
    patch engine_data_aircraft_flight_log_path(@aircraft, flight), params: { flight_log: { engine_data: upload } }
    assert_redirected_to aircraft_flight_log_path(@aircraft, flight)
    refute flight.reload.engine_data.attached?
    get aircraft_flight_log_path(@aircraft, flight)
    refute_includes response.body, "Attach engine monitor data"

    sign_in @pilot
    get aircraft_flight_log_path(@aircraft, flight)
    assert_includes response.body, "Attach engine monitor data"
    patch engine_data_aircraft_flight_log_path(@aircraft, flight), params: { flight_log: { engine_data: upload } }
    assert flight.reload.engine_data.attached?

    sign_in @owner
    delete engine_data_aircraft_flight_log_path(@aircraft, flight)
    perform_enqueued_jobs
    refute flight.reload.engine_data.attached?
  end

  test "warns when the recording is from another aircraft" do
    @aircraft.update!(tail_number: "N54321")
    flight = @aircraft.flight_logs.create!(date: Date.current, tach_time: 0.1, engine_data: upload)
    sign_in @owner
    get aircraft_flight_log_path(@aircraft, flight)
    assert_includes response.body, "This recording is from <strong>N12345</strong>"
  end
end

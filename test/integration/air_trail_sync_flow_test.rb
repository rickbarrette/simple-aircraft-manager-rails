require "test_helper"

class AirTrailSyncFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @fake = FakeAirTrail.new(self)
    @user = create_user
    @a = create_aircraft(owner: @user, tail_number: "N12345", tach_time: 100)
    sign_in @user
  end

  def connect(key: "at_secret")
    post air_trail_connection_path, params: { air_trail_connection: { base_url: "#{FakeAirTrail::BASE}/", api_key: key, enabled: "1" } }
  end

  test "connect, see status, and flights sync automatically when logged and deleted" do
    get air_trail_connection_path
    assert_response :success
    connect
    assert_redirected_to air_trail_connection_path
    follow_redirect!
    assert_match "Connected to AirTrail as ricky", response.body
    assert_equal "https://airtrail.test", @user.air_trail_connection.base_url

    perform_enqueued_jobs do
      post aircraft_flight_logs_path(@a), params: { flight_log: { date: Date.current, tach_out: 100, tach_in: 101.2,
                                                                  departure_location: "KOQU", destination_location: "KBID" } }
    end
    flight = @a.flight_logs.last
    sync = flight.air_trail_syncs.first
    assert_equal "synced", sync.status
    assert @fake.flights.key?(sync.remote_id)

    get aircraft_flight_log_path(@a, flight)
    assert_select "span.badge-green", text: "Synced"

    perform_enqueued_jobs { delete aircraft_flight_log_path(@a, flight) }
    assert_not @fake.flights.key?(sync.remote_id)
  end

  test "missing scopes and bad keys are reported" do
    @fake.scopes = %w[profile.read flight.create.own]
    connect
    follow_redirect!
    assert_match "missing scopes", response.body
    assert_match "tracks.write", response.body

    @user.air_trail_connection.destroy!
    connect(key: "wrong")
    follow_redirect!
    assert_match "Invalid API key", response.body
  end

  test "updating keeps the stored key when left blank; sync all runs a backfill; disconnect" do
    connect
    patch air_trail_connection_path, params: { air_trail_connection: { base_url: FakeAirTrail::BASE, api_key: "" } }
    assert_equal "at_secret", @user.air_trail_connection.reload.api_key

    assert_enqueued_with(job: AirTrailBackfillJob) { post sync_air_trail_connection_path }
    delete air_trail_connection_path
    assert_nil @user.reload.air_trail_connection
  end

  test "flights by users without a connection don't enqueue anything" do
    assert_no_enqueued_jobs(only: AirTrailPushJob) do
      @a.flight_logs.create!(date: Date.current, tach_time: 1, user: @user, departure_location: "KOQU", destination_location: "KBID")
    end
  end
end

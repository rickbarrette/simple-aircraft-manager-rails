require "test_helper"

# Logging a flight with no signal: the form works offline (kept by the service
# worker), queues on the device, and is sent once; sending it twice doesn't
# log it twice.
class OfflineFlightsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345", tach_time: 1000)
    sign_in @owner
  end

  test "the form carries a one-time key and the offline controller; the same key is logged once" do
    get new_aircraft_flight_log_path(@a)
    assert_select "form[data-controller=offline-form][data-offline-form-kind-value=flight][data-offline-form-tail-value=N12345]"
    assert_select "input[type=hidden][name='flight_log[client_key]']"
    assert_select "body[data-controller~=offline-sync] [data-offline-sync-target=banner]"

    params = { flight_log: { date: "2026-11-08", tach_out: 1000, tach_in: 1001.2, departure_location: "KOQU", destination_location: "KBID", client_key: "key-1" } }
    post aircraft_flight_logs_path(@a), params: params
    assert_redirected_to aircraft_flight_logs_path(@a)
    post aircraft_flight_logs_path(@a), params: params # resent after a dropped connection
    assert_redirected_to aircraft_flight_logs_path(@a)
    assert_equal 1, @a.flight_logs.where(client_key: "key-1").count
    assert_in_delta 1001.2, @a.reload.tach_time, 0.001 # hours applied once
  end

  test "the service worker keeps Log Flight forms and the offline page links them" do
    get pwa_service_worker_path(format: :js)
    assert_includes response.body, %q(const FORMS = /^\/aircraft\/\d+\/(flight_logs|squawks)\/new$/)
    assert Rails.public_path.join("offline.js").read.include?("sam-offline-forms")
  end
end

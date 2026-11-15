require "test_helper"

# A signal so weak requests hang counts as none: pages fall back to the
# offline page within a time limit, and the Log Flight / Report Squawk forms
# are kept on the device instead of waiting.
class WeakSignalTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner)
  end

  test "the service worker gives up on pages after a time limit and sends every page to the offline page" do
    get pwa_service_worker_path(format: :js)
    js = response.body
    assert_match(/const NETWORK_TIMEOUT = 10 \* 1000/, js)
    assert_match(/const wait = since < STILL_OFFLINE \? OFFLINE_TIMEOUT : NETWORK_TIMEOUT/, js) # quick while offline
    assert_match(/\} else if \(wantsHtml\) \{\s*\/\/[^\n]*\n\s*event\.respondWith\(page\(request\)\)/, js)
    assert_match "if (request.mode !== \"navigate\") throw error\n    return offlinePage()", js
    # downloads built while you wait get no time limit
    downloads = Regexp.new(js[%r{const DOWNLOADS = /(.+)/$}, 1])
    %w[/aircraft/1/export /aircraft/1/records /aircraft/1/logbook/print.pdf].each { |path| assert_match downloads, path }
    %w[/aircraft/1 /aircraft/1/flight_logs/new /aircraft/1/documents/2].each { |path| assert_no_match downloads, path }
  end

  test "the flight and squawk forms limit the wait and say they're sending" do
    sign_in @owner
    get new_aircraft_flight_log_path(@a)
    assert_select "form[data-controller~=offline-form][data-action*='turbo:before-fetch-request->offline-form#limit']"
    assert_select "input[type=submit][data-turbo-submits-with='Sending…']", 2

    get new_aircraft_squawk_path(@a)
    assert_select "form[data-controller~=offline-form][data-action*='turbo:before-fetch-request->offline-form#limit']"
    assert_select "input[type=submit][data-turbo-submits-with='Sending…']", 1
  end
end

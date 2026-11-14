require "test_helper"

# The installed app: the offline page, offline squawks, the per-user offline
# queue and sign-out cleanup, home-screen shortcuts, and push notifications.
class PwaFeaturesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345")
  end

  test "the offline page is public, in the app's language, and has no inline script" do
    get offline_path
    assert_response :success
    assert_select "html[lang=en]"
    assert_select "h1", "You're offline"
    assert_select "script[src='/offline.js']"
    assert_no_match(/onclick=/, response.body)
    assert_select "#forms[data-flight='Log a flight: %{tail}'][data-squawk='Report a squawk: %{tail}']"
  end

  test "pages say who's signed in and when they were rendered; signing out clears the device" do
    sign_in @owner
    get aircraft_path(@a)
    assert_select "meta[name=current-user][content='#{@owner.id}']"
    assert_select "meta[name=rendered-at]"
    assert_select "meta[name=aircraft-tail][content=N12345]" # the offline page lists saved overviews by tail
    assert_select "body[data-controller~=page-age] [data-page-age-target=banner]"
    assert_select "form[action='#{session_path}'][data-controller=sign-out]", minimum: 1
  end

  test "updating the meters without a flight asks for confirmation, showing the change" do
    sign_in @owner
    get aircraft_path(@a)
    assert_select "form[action='#{hours_aircraft_path(@a)}'][data-controller=hours-confirm][data-action='submit->hours-confirm#confirm'][data-hours-confirm-tach-value='1000.0']" do
      assert_select "input[name=tach_time][data-hours-confirm-target=tach]"
      assert_select "input[name=hobbs_time][data-hours-confirm-target=hobbs]"
    end

    patch hours_aircraft_path(@a), params: { tach_time: "1001.4", hobbs_time: "1.2" }
    assert_equal "Tach 1,000.0 → 1,001.4 (+1.4) · Hobbs 0.0 → 1.2 (+1.2). In-service components moved +1.4 hrs; no flight was logged.", flash[:notice]
    patch hours_aircraft_path(@a), params: { tach_time: "1001.0" }
    assert_equal "Corrected: Tach 1,001.4 → 1,001.0 (−0.4). In-service components moved −0.4 hrs; no flight was logged.", flash[:notice]
  end

  test "every page lists what to save ahead of time for working offline: each of your aircraft's forms and pages" do
    other = create_aircraft(tail_number: "N99999") # not this pilot's
    sign_in @pilot
    get root_path
    assert_select "body[data-controller~=offline-prep]"
    saved = JSON.parse(css_select("body").first["data-offline-prep-aircraft-value"])
    assert_equal [ { "tail" => "N12345", "pages" => [ aircraft_path(@a), aircraft_weight_balance_records_path(@a) ],
                     "flight" => new_aircraft_flight_log_path(@a), "squawk" => new_aircraft_squawk_path(@a) } ], saved
    assert_not_includes saved.to_s, aircraft_path(other)

    @a.picture.attach(io: StringIO.new(file_fixture_png), filename: "plane.png", content_type: "image/png")
    get root_path
    picture = JSON.parse(css_select("body").first["data-offline-prep-aircraft-value"]).first["picture"]
    shown = css_select("img[src*='/rails/active_storage/blobs/redirect/']").first["src"]
    # Links expire, so they differ; both carry the same upload id, which the saved copy is filed under.
    blob_id = ->(url) { JSON.parse(Base64.decode64(CGI.unescape(url[%r{/blobs/redirect/([^/]+?)--}, 1])))["_rails"]["data"] }
    assert_equal @a.picture.blob.id, blob_id.(picture)
    assert_equal @a.picture.blob.id, blob_id.(shown)
  end

  test "squawks can be reported offline and are received once" do
    sign_in @pilot
    get new_aircraft_squawk_path(@a)
    assert_select "form[data-controller~=offline-form][data-offline-form-kind-value=squawk][data-offline-form-tail-value=N12345]"
    assert_select "input[type=hidden][name='squawk[client_key]']"

    params = { squawk: { priority: 1, issue_reported: "Left landing light inop", client_key: "sq-1" } }
    2.times { post aircraft_squawks_path(@a), params: params } # resent after a dropped connection
    assert_equal 1, @a.squawks.where(client_key: "sq-1").count

    get edit_aircraft_squawk_path(@a, @a.squawks.last) # pilots can't edit; owners' edit form isn't queued
    sign_in @owner
    get edit_aircraft_squawk_path(@a, @a.squawks.last)
    assert_select "form[data-controller~=offline-form]", count: 0
  end

  test "home-screen shortcuts open the form for your only aircraft, or let you choose" do
    sign_in @pilot
    get log_flight_shortcut_path
    assert_redirected_to new_aircraft_flight_log_path(@a)
    get report_squawk_shortcut_path
    assert_redirected_to new_aircraft_squawk_path(@a)

    other = create_aircraft(pilot: @pilot, tail_number: "N54321")
    get report_squawk_shortcut_path
    assert_response :success
    assert_select "a[href='#{new_aircraft_squawk_path(@a)}']", /N12345/
    assert_select "a[href='#{new_aircraft_squawk_path(other)}']", /N54321/
  end

  test "the service worker keeps pre-flight pages, sends in the background and shows notifications" do
    get pwa_service_worker_path(format: :js)
    body = response.body
    assert_includes body, %q(const PAGES = /^\/$|^\/aircraft\/\d+(\/weight_balance)?$/) # the Fleet page too: the app opens offline
    assert_includes body, 'addEventListener("sync"'
    assert_includes body, 'addEventListener("push"'
    assert_includes body, 'addEventListener("notificationclick"'
    assert_includes body, "if (item.user && item.user !== user) continue" # only the signed-in user's items
  end

  test "the profile offers installing and notifications for this device" do
    sign_in @owner
    get edit_profile_path
    assert_select "#device [data-controller=install] [data-action='install#install']"
    assert_select "#device [data-controller=push][data-push-key-value='#{PushKeys.public_key}'][data-push-url-value='#{push_subscription_path}']"
  end

  test "devices subscribe and unsubscribe; only browser push services; signed-in users only" do
    post push_subscription_path, params: { subscription: subscription_params("https://fcm.googleapis.com/fcm/send/a") }, as: :json
    assert_redirected_to new_session_path

    sign_in @owner
    post push_subscription_path, params: { subscription: subscription_params("https://fcm.googleapis.com/fcm/send/a") }, as: :json
    assert_response :created
    post push_subscription_path, params: { subscription: subscription_params("https://internal.example.com/b") }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "https://fcm.googleapis.com/fcm/send/a" ], @owner.push_subscriptions.pluck(:endpoint)

    assert_enqueued_with(job: PushNotificationJob) { post test_push_subscription_path, as: :json }
    delete push_subscription_path, params: { endpoint: "https://fcm.googleapis.com/fcm/send/a" }, as: :json
    assert_empty @owner.push_subscriptions.reload
  end

  test "notifications are encrypted to each device; gone devices are forgotten" do
    live = subscribe(@pilot, "https://fcm.googleapis.com/fcm/send/live")
    gone = subscribe(@pilot, "https://fcm.googleapis.com/fcm/send/gone")
    stub_request(:post, live.endpoint).to_return(status: 201)
    stub_request(:post, gone.endpoint).to_return(status: 410)

    PushNotificationJob.perform_now([ @pilot.id ], "grounding_squawk", "/aircraft/#{@a.id}/squawks", "t", { "tail" => "N12345", "issue" => "Mag drop" })
    assert_requested(:post, live.endpoint) { |req| req.headers["Content-Encoding"] == "aes128gcm" && req.headers["Authorization"].start_with?("vapid ") }
    assert PushSubscription.exists?(live.id)
    assert_not PushSubscription.exists?(gone.id)
  end

  test "a grounding squawk notifies the aircraft's other people; a minor one doesn't" do
    subscribe(@owner, "https://fcm.googleapis.com/fcm/send/owner")
    subscribe(@pilot, "https://fcm.googleapis.com/fcm/send/pilot")
    sign_in @pilot
    assert_enqueued_with(job: PushNotificationJob, args: ->(args) { args[0] == [ @owner.id ] && args[1] == "grounding_squawk" }) do
      post aircraft_squawks_path(@a), params: { squawk: { priority: 0, issue_reported: "Mag drop over 200 rpm" } }
    end
    assert_no_enqueued_jobs(only: PushNotificationJob) do
      post aircraft_squawks_path(@a), params: { squawk: { priority: 3, issue_reported: "Seat cushion worn" } }
    end
  end

  test "a request to sign reaches someone who already has an account" do
    mechanic = create_user("mech@example.com")
    subscribe(mechanic, "https://fcm.googleapis.com/fcm/send/mech")
    entry = @a.logbook_entries.create!(date: Date.current, entry_type: "MAINTENANCE", log_type: "AC", text: "Oil changed")
    sign_in @owner
    assert_enqueued_with(job: PushNotificationJob, args: ->(args) { args[0] == [ mechanic.id ] && args[1] == "signing_request" }) do
      post aircraft_logbook_entry_signing_invitations_path(@a, entry), params: { signing_invitation: { email: "mech@example.com" } }
    end
  end

  test "owners hear once about each item that becomes overdue" do
    subscribe(@owner, "https://fcm.googleapis.com/fcm/send/owner")
    annual = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12).tap { _1.aircraft << @a }
    @a.inspection_records.create!(inspection_type: annual, date: 13.months.ago.to_date)

    assert_enqueued_with(job: PushNotificationJob, args: ->(args) { args[0] == [ @owner.id ] && args[1] == "overdue" && args[4][:count] == 1 }) do
      OverdueNotificationJob.perform_now
    end
    assert_no_enqueued_jobs(only: PushNotificationJob) { OverdueNotificationJob.perform_now } # already told

    @a.inspection_records.create!(inspection_type: annual, date: Date.current) # done: forgotten
    OverdueNotificationJob.perform_now
    assert_empty @a.reload.notified_issue_keys
  end

  private

  def file_fixture_png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  def subscribe(user, endpoint) = user.push_subscriptions.create!(endpoint: endpoint, **device_keys)

  def subscription_params(endpoint) = { endpoint: endpoint, keys: device_keys }

  # A browser's subscription keys: its P-256 public key and a 16-byte secret.
  def device_keys
    key = OpenSSL::PKey::EC.generate("prime256v1")
    { p256dh: Base64.urlsafe_encode64(key.public_key.to_octet_string(:uncompressed), padding: false),
      auth: Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false) }
  end
end

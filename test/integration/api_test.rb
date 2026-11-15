require "test_helper"

# The REST API (docs/api.md): tokens, what each kind may reach, the read
# endpoints, squawk writes, idempotent retries and webhooks.
class ApiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@example.com", admin: true)
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @outsider = create_user("outsider@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345")
    @other = create_aircraft(owner: @outsider, tail_number: "N99999")
  end

  test "no token, a wrong one or a revoked one is refused" do
    get "/api/v1/me"
    assert_response :unauthorized
    get "/api/v1/me", headers: bearer("sam_nope")
    assert_response :unauthorized
    token = personal(@pilot)
    token.revoke!
    get "/api/v1/me", headers: bearer(token.token)
    assert_response :unauthorized
  end

  test "a personal token acts as its owner and reaches exactly their aircraft" do
    token = personal(@pilot)
    get "/api/v1/me", headers: bearer(token.token)
    assert_response :success
    assert_equal "pilot@example.com", body.dig("data", "acting_as", "email")
    get "/api/v1/aircraft", headers: bearer(token.token)
    assert_equal [ "N12345" ], body["data"].map { _1["tail_number"] }
    get "/api/v1/aircraft/#{@other.id}", headers: bearer(token.token)
    assert_response :not_found
    assert token.reload.last_used_at, "last use is recorded"
  end

  test "a disabled user's token stops working" do
    token = personal(@pilot)
    @pilot.update_column(:disabled_at, Time.current)
    get "/api/v1/me", headers: bearer(token.token)
    assert_response :unauthorized
  end

  test "an integration reaches only its aircraft, narrowed to the person it acts for" do
    token = integration(aircraft: [ @a, @other ])
    get "/api/v1/aircraft", headers: bearer(token.token)
    assert_equal %w[N12345 N99999], body["data"].map { _1["tail_number"] }.sort
    get "/api/v1/aircraft", headers: bearer(token.token, as: @pilot)
    assert_equal [ "N12345" ], body["data"].map { _1["tail_number"] }
    get "/api/v1/aircraft", headers: bearer(token.token, as: "nobody@example.com")
    assert_response :unprocessable_entity
    assert_equal "unknown_user", body.dig("error", "code")
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.create!(name: "x", kind: "integration", user: @owner, scopes: %w[read]) }
  end

  test "the read endpoints describe the aircraft, its parts, what's due, squawks and entries" do
    engine = @a.components.create!(component_type: ComponentType.create!(name: "Engine"), manufacturer: "Lycoming", model: "O-320",
                                   serial_number: "L-1", date_in_service: Date.new(2020, 1, 1), hours_in_service: 100, tbo_hours: 2000)
    @a.squawks.create!(issue_reported: "Left brake soft", priority: 1, reported_by: @pilot, external_ref: "redmine:issue:1")
    @a.logbook_entries.create!(date: Date.current, log_type: "ENG", entry_type: "MAINTENANCE", text: "Oil changed")
    h = bearer(personal(@owner).token)

    get "/api/v1/aircraft/#{@a.id}", headers: h
    assert_equal "N12345", body.dig("data", "tail_number")
    assert body.dig("data", "airworthiness", "status")
    get "/api/v1/aircraft/#{@a.id}/components", headers: h
    assert_equal [ [ engine.id, "Engine", "L-1", 2000 ] ], body["data"].map { [ _1["id"], _1["type"], _1["serial_number"], _1.dig("tbo", "hours") ] }
    get "/api/v1/aircraft/#{@a.id}/due", headers: h
    assert_kind_of Array, body["data"]
    get "/api/v1/aircraft/#{@a.id}/squawks", headers: h
    assert_equal [ "Left brake soft" ], body["data"].map { _1["issue_reported"] }
    get "/api/v1/squawks", params: { external_ref: "redmine:issue:1" }, headers: h
    assert_equal 1, body["data"].size
    get "/api/v1/aircraft/#{@a.id}/logbook_entries", params: { log: "ENG" }, headers: h
    assert_equal [ [ "Oil changed", false ] ], body["data"].map { [ _1["text"], _1["signed"] ] }
    get "/api/v1/aircraft/#{@a.id}/inspections", headers: h
    assert_response :success
    get "/api/v1/aircraft/#{@a.id}/ads", headers: h
    assert_response :success
  end

  test "lists page with after and limit" do
    5.times { |i| @a.squawks.create!(issue_reported: "Issue #{i}", priority: 2) }
    h = bearer(personal(@owner).token)
    get "/api/v1/aircraft/#{@a.id}/squawks", params: { limit: 2 }, headers: h
    first = body
    assert_equal 2, first["data"].size
    get "/api/v1/aircraft/#{@a.id}/squawks", params: { limit: 2, after: first["next_after"] }, headers: h
    assert_equal 2, body["data"].size
    assert_empty first["data"].map { _1["id"] } & body["data"].map { _1["id"] }
  end

  test "a pilot can report a squawk; it's announced and attributed to them, via the token" do
    token = personal(@pilot)
    post "/api/v1/aircraft/#{@a.id}/squawks", params: { squawk: { issue_reported: "Mag drop 200 rpm", priority: 0, external_ref: "redmine:issue:9" } },
                                              headers: bearer(token.token), as: :json
    assert_response :created
    squawk = Squawk.find(body.dig("data", "id"))
    assert_equal [ @pilot, true, "redmine:issue:9" ], [ squawk.reported_by, squawk.grounding?, squawk.external_ref ]
    version = squawk.versions.last
    assert_equal [ @pilot.id, token.id ], [ version.user_id, version.api_token_id ]
    assert_equal token.id, JSON.parse(version.payload)["api_token_id"], "in the hashed payload"
    assert @a.events.exists?(category: "squawk")
  end

  test "integration writes must say who they're for, and need the write scope" do
    reader = integration(aircraft: [ @a ], scopes: %w[read])
    writer = integration(aircraft: [ @a ], scopes: %w[read squawks:write])
    params = { squawk: { issue_reported: "Oil leak" } }
    post "/api/v1/aircraft/#{@a.id}/squawks", params: params, headers: bearer(writer.token), as: :json
    assert_equal "on_behalf_of_required", body.dig("error", "code")
    post "/api/v1/aircraft/#{@a.id}/squawks", params: params, headers: bearer(reader.token, as: @pilot), as: :json
    assert_equal "missing_scope", body.dig("error", "code")
    post "/api/v1/aircraft/#{@a.id}/squawks", params: params, headers: bearer(writer.token, as: @outsider), as: :json
    assert_response :not_found, "the person must have access to the aircraft"
    post "/api/v1/aircraft/#{@a.id}/squawks", params: params, headers: bearer(writer.token, as: @pilot), as: :json
    assert_response :created
  end

  test "only owners change a squawk's details; anyone who may write can set its external_ref" do
    squawk = @a.squawks.create!(issue_reported: "Light out", priority: 2)
    pilot_h = bearer(personal(@pilot).token)
    patch "/api/v1/squawks/#{squawk.id}", params: { squawk: { priority: 0 } }, headers: pilot_h, as: :json
    assert_response :forbidden
    patch "/api/v1/squawks/#{squawk.id}", params: { squawk: { external_ref: "redmine:issue:7" } }, headers: pilot_h, as: :json
    assert_response :success
    patch "/api/v1/squawks/#{squawk.id}", params: { squawk: { priority: 1, notes: "Bulb ordered" } }, headers: bearer(personal(@owner).token), as: :json
    assert_equal [ 1, "Bulb ordered", "redmine:issue:7" ], squawk.reload.then { [ _1.priority, _1.notes, _1.external_ref ] }
  end

  test "a retry with the same Idempotency-Key gets the first answer, not a second squawk" do
    h = bearer(personal(@pilot).token).merge("Idempotency-Key" => "abc-123")
    params = { squawk: { issue_reported: "Door seal torn" } }
    post "/api/v1/aircraft/#{@a.id}/squawks", params: params, headers: h, as: :json
    first = body.dig("data", "id")
    post "/api/v1/aircraft/#{@a.id}/squawks", params: params, headers: h, as: :json
    assert_equal [ first, "true" ], [ body.dig("data", "id"), response.headers["Idempotent-Replay"] ]
    assert_equal 1, @a.squawks.count
    post "/api/v1/aircraft/#{@a.id}/squawks", params: { squawk: { issue_reported: "Different" } }, headers: h, as: :json
    assert_response :conflict
  end

  test "errors are JSON with the fields at fault" do
    post "/api/v1/aircraft/#{@a.id}/squawks", params: { squawk: { issue_reported: "" } }, headers: bearer(personal(@pilot).token), as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid", body.dig("error", "code")
    assert body.dig("error", "fields", "issue_reported")
    post "/api/v1/aircraft/#{@a.id}/squawks", params: "{not json", headers: bearer(personal(@pilot).token).merge("Content-Type" => "application/json")
    assert_response :bad_request
  end

  test "webhooks go to integrations that reach the aircraft, signed with their secret" do
    token = integration(aircraft: [ @a ])
    endpoint = token.webhook_endpoints.create!(url: "https://hooks.example.com/sam", secret: "s" * 32, events: %w[squawk.created squawk.resolved])
    other = integration(aircraft: [ @other ]).webhook_endpoints.create!(url: "https://elsewhere.example.com/", secret: "t" * 32, events: %w[squawk.created])
    stub_request(:post, "https://hooks.example.com/sam").to_return(status: 204)

    perform_enqueued_jobs { @a.squawks.create!(issue_reported: "Prop nick", priority: 1) }
    assert_requested(:post, "https://hooks.example.com/sam") do |req|
      t, sig = req.headers["Sam-Signature"].scan(/t=(\d+),v1=(\h+)/).first
      sig == OpenSSL::HMAC.hexdigest("SHA256", "s" * 32, "#{t}.#{req.body}") && JSON.parse(req.body)["event"] == "squawk.created"
    end
    assert_equal [ "delivered", 204 ], endpoint.deliveries.last.then { [ _1.status, _1.response_status ] }
    assert_empty other.deliveries, "not for an integration that doesn't reach the aircraft"
  end

  test "a failing webhook is retried, then marked failed" do
    endpoint = integration(aircraft: [ @a ]).webhook_endpoints.create!(url: "https://hooks.example.com/sam", secret: "s" * 32, events: %w[squawk.created])
    stub_request(:post, "https://hooks.example.com/sam").to_return(status: 500)
    perform_enqueued_jobs { @a.squawks.create!(issue_reported: "Tire worn", priority: 2) }
    delivery = endpoint.deliveries.last
    assert_equal [ "failed", WebhookDeliveryJob::ATTEMPTS ], [ delivery.status, delivery.attempts ]
  end

  test "a webhook pointed at the server itself is never sent" do
    endpoint = integration(aircraft: [ @a ]).webhook_endpoints.create!(url: "http://127.0.0.1:3000/hook", secret: "s" * 32, events: %w[squawk.created])
    perform_enqueued_jobs { @a.squawks.create!(issue_reported: "Seat rail", priority: 2) }
    assert_equal "failed", endpoint.deliveries.last.status
    assert_not_requested :post, "http://127.0.0.1:3000/hook"
  end

  private

  def personal(user) = ApiToken.create!(name: "script", kind: "personal", user: user, scopes: %w[read squawks:write])

  def integration(aircraft:, scopes: %w[read squawks:write])
    ApiToken.create!(name: "Redmine", kind: "integration", user: @admin, scopes: scopes, aircraft_ids: aircraft.map(&:id))
  end

  def bearer(token, as: nil)
    { "Authorization" => "Bearer #{token}" }.tap do |h|
      h["SAM-On-Behalf-Of"] = as.respond_to?(:email_address) ? as.email_address : as if as
    end
  end

  def body = JSON.parse(response.body)
end

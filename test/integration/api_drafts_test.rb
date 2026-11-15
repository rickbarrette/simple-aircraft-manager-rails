require "test_helper"

# Draft logbook entries through the API: one unsigned entry per logbook,
# signed in the app; the squawks and inspections they resolve wait for the
# signatures.
class ApiDraftsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @admin = create_user("admin@example.com", admin: true)
    @owner = create_user("owner@example.com")
    @mech = create_user("mech@example.com").tap { _1.update!(name: "Sam Mechanic") }
    @a = create_aircraft(owner: @owner, pilot: @mech, tail_number: "N12345")
    @ap = @mech.certificates.create!(kind: "AP", number: "7654321")
    @ia = @mech.certificates.create!(kind: "IA", number: "7654321", expires_on: Date.current + 200)
    @brake = @a.squawks.create!(issue_reported: "Left brake soft", priority: 0, reported_by: @mech)
    @annual = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12).tap { _1.aircraft << @a }
    @token = ApiToken.create!(name: "Redmine", kind: "integration", user: @admin, scopes: %w[read drafts:write], aircraft_ids: [ @a.id ])
  end

  test "a visit's work becomes one draft entry per logbook; nothing is resolved until all are signed" do
    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: batch_params, headers: headers(as: @owner), as: :json
    assert_response :created
    data = JSON.parse(response.body)["data"]
    batch = DraftBatch.find(data["id"])
    assert_equal [ "AC", "ENG" ], data["entries"].map { _1["log"] }
    ac, eng = batch.entries.order(:log_type).to_a
    assert_equal "Replaced left brake linings.\n\nAnnual inspection.", ac.text
    assert_equal [ "INSPECTION", "MAINTENANCE", "1234.5" ], [ ac.entry_type, eng.entry_type, eng.aircraft_hours_at_entry.to_s ]
    assert_equal "redmine:issue:2,redmine:issue:3", ac.external_ref
    assert data["entries"].all? { _1["sign_url"] && _1["invitation_url"].nil? }
    assert @a.events.exists?(category: "logbook")

    sign_in @mech
    get new_aircraft_logbook_entry_signature_path(@a, ac)
    assert_includes response.body, "When all 2 entries of this draft are signed, this also:"
    assert_includes response.body, "Resolves the squawk: Left brake soft"
    assert_includes response.body, "Records the Annual as completed"

    sign(ac, @ia)
    assert ac.reload.signed?
    assert_equal "approved", ac.inspection_result
    assert_not @brake.reload.resolved?, "held until every entry is signed"
    assert_empty @a.inspection_records

    webhook = @token.webhook_endpoints.create!(url: "https://redmine.example.com/sam", secret: "s" * 32, events: %w[draft_batch.completed])
    stub_request(:post, "https://redmine.example.com/sam").to_return(status: 200)
    perform_enqueued_jobs { sign(eng) }
    assert @brake.reload.resolved?
    assert_equal ac, @brake.logbook_entry, "resolved by the airframe entry that described the work"
    assert_equal [ [ @annual, ac ] ], @a.inspection_records.map { [ _1.inspection_type, _1.logbook_entry ] }
    assert_equal "completed", batch.reload.status
    assert_equal @mech.id, @brake.versions.last.user_id, "the change is attributed to the person who signed"
    assert_equal "completed", JSON.parse(webhook.deliveries.last.payload).dig("data", "status")
  end

  test "a signer without an account gets a link, returned to the caller (and emailed only when asked)" do
    params = batch_params
    params[:draft_batch][:signer] = { email: "Outside.Mech@Example.com" }
    assert_no_emails do
      perform_enqueued_jobs { post "/api/v1/aircraft/#{@a.id}/draft_batches", params: params, headers: headers(as: @owner), as: :json }
    end
    entries = JSON.parse(response.body).dig("data", "entries")
    assert entries.all? { _1["invitation_url"].to_s.include?("/sign/") }
    token = entries.first["invitation_url"][%r{/sign/(.+)\z}, 1]
    invitation = SigningInvitation.find_usable(token)
    assert_equal "outside.mech@example.com", invitation.email
  end

  test "drafts are for owners: an integration must act for one, with the drafts scope" do
    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: batch_params, headers: headers(as: @mech), as: :json
    assert_response :forbidden
    assert_equal "not_permitted", JSON.parse(response.body).dig("error", "code")
    @token.update!(scopes: %w[read])
    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: batch_params, headers: headers(as: @owner), as: :json
    assert_equal "missing_scope", JSON.parse(response.body).dig("error", "code")
    assert_equal 0, DraftBatch.count
  end

  test "bad drafts are refused with the fields at fault, and nothing is made" do
    params = { draft_batch: { date: "not a date", items: [ { log: "WING", text: "" } ], completes_inspections: [ { inspection_type_id: 999 } ],
                              signer: { email: "nope" } } }
    params[:draft_batch][:items].first[:resolves_squawks] = [ @brake.id + 1000 ]
    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: params, headers: headers(as: @owner), as: :json
    assert_response :unprocessable_entity
    fields = JSON.parse(response.body).dig("error", "fields")
    assert_equal %w[aircraft_hours completes_inspections.0 completes_inspections.0.result date items.0.log items.0.text resolves_squawks signer.email].sort, fields.keys.sort
    assert_equal 0, LogbookEntry.count
  end

  test "an unsigned draft can be withdrawn; once part is signed it can't" do
    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: batch_params, headers: headers(as: @owner), as: :json
    batch = DraftBatch.find(JSON.parse(response.body).dig("data", "id"))
    delete "/api/v1/draft_batches/#{batch.id}", headers: headers(as: @owner)
    assert_response :success
    assert_equal [ "withdrawn", 0 ], [ batch.reload.status, batch.entries.count ]
    assert_not @brake.reload.resolved?

    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: batch_params, headers: headers(as: @owner).merge("Idempotency-Key" => "second"), as: :json
    second = DraftBatch.find(JSON.parse(response.body).dig("data", "id"))
    sign_in @mech
    sign(second.entries.find_by(log_type: "ENG"))
    delete "/api/v1/draft_batches/#{second.id}", headers: headers(as: @owner)
    assert_response :conflict
  end

  test "drafts can be found by the other system's reference" do
    post "/api/v1/aircraft/#{@a.id}/draft_batches", params: batch_params, headers: headers(as: @owner), as: :json
    get "/api/v1/draft_batches", params: { external_ref: "redmine:visit:77" }, headers: headers
    assert_equal 1, JSON.parse(response.body)["data"].size
    get "/api/v1/aircraft/#{@a.id}/draft_batches", params: { status: "awaiting_signature" }, headers: headers
    assert_equal 1, JSON.parse(response.body)["data"].size
  end

  private

  def batch_params
    { draft_batch: {
      date: Date.current.iso8601, aircraft_hours: "1234.5", external_ref: "redmine:visit:77",
      items: [
        { log: "ENG", text: "Changed oil and filter.", external_ref: "redmine:issue:1" },
        { log: "AC", text: "Replaced left brake linings.", resolves_squawks: [ @brake.id ], external_ref: "redmine:issue:2" },
        { log: "AC", text: "Annual inspection.", external_ref: "redmine:issue:3" }
      ],
      completes_inspections: [ { inspection_type_id: @annual.id, result: "approved" } ]
    } }
  end

  def headers(as: nil)
    { "Authorization" => "Bearer #{@token.token}" }.tap { |h| h["SAM-On-Behalf-Of"] = as.email_address if as }
  end

  def sign(entry, certificate = @ap)
    post aircraft_logbook_entry_signature_path(@a, entry), params: { certificate_id: certificate.id, password: "test-password-123", confirm: "1" }
  end
end

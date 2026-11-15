require "test_helper"

# Making and revoking API tokens: personal ones on Profile, integrations
# (with their webhooks) under Admin.
class ApiManagementTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@example.com", admin: true)
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @admin, pilot: @pilot, tail_number: "N12345")
  end

  test "a personal token is shown once, listed by its first characters, and can be revoked" do
    sign_in @pilot
    get edit_profile_path
    assert_select "#api form[action='#{api_tokens_path}']"
    post api_tokens_path, params: { api_token: { name: "My script", scopes: %w[read squawks:write bogus] } }
    assert_response :success
    token = @pilot.api_tokens.last
    shown = css_select("input[readonly]").first["value"]
    assert_equal token, ApiToken.authenticate(shown)
    assert_equal %w[read squawks:write], token.scopes

    get edit_profile_path
    assert_select "#api", text: /My script/
    assert_no_match shown, response.body, "not shown again"
    delete api_token_path(token)
    assert token.reload.revoked?
    assert_nil ApiToken.authenticate(shown)
  end

  test "you can't revoke someone else's token" do
    other = ApiToken.create!(name: "theirs", kind: "personal", user: @admin, scopes: %w[read])
    sign_in @pilot
    delete api_token_path(other)
    assert_response :not_found
    assert_not other.reload.revoked?
  end

  test "an admin makes an integration with a webhook; the token and secret are shown once" do
    sign_in @admin
    get admin_integrations_path
    assert_response :success
    post admin_integrations_path, params: { api_token: { name: "Redmine", scopes: %w[read squawks:write], aircraft_ids: [ @a.id ] },
                                            webhook: { url: "https://redmine.example.com/sam", events: %w[squawk.created entry.signed] } }
    assert_response :success
    integration = ApiToken.integration.last
    assert_equal [ "Redmine", [ @a.id ], @admin ], [ integration.name, integration.aircraft_ids, integration.user ]
    token, secret = css_select("input[readonly]").map { _1["value"] }
    assert_equal integration, ApiToken.authenticate(token)
    endpoint = integration.webhook_endpoints.sole
    assert_equal [ secret, %w[squawk.created entry.signed] ], [ endpoint.secret, endpoint.events ]

    get admin_integration_path(integration)
    assert_response :success
    assert_no_match token, response.body
    assert_no_match secret, response.body
  end

  test "editing an integration changes its reach and webhook; a new secret replaces the old" do
    integration = ApiToken.create!(name: "Redmine", kind: "integration", user: @admin, scopes: %w[read], aircraft_ids: [])
    sign_in @admin
    patch admin_integration_path(integration), params: { api_token: { name: "Redmine", scopes: %w[read], aircraft_ids: [ @a.id ] },
                                                         webhook: { url: "https://redmine.example.com/sam", events: %w[squawk.resolved] } }
    assert_redirected_to admin_integration_path(integration)
    assert_equal [ @a.id ], integration.reload.aircraft_ids
    old = integration.webhook_endpoints.sole.secret
    post new_secret_admin_integration_path(integration)
    assert_not_equal old, integration.webhook_endpoints.sole.reload.secret
    patch admin_integration_path(integration), params: { api_token: { name: "Redmine", scopes: %w[read], aircraft_ids: [ @a.id ] }, webhook: { url: "" } }
    assert_empty integration.webhook_endpoints.reload, "clearing the address removes the webhook"
  end

  test "an invalid integration shows the form again" do
    sign_in @admin
    post admin_integrations_path, params: { api_token: { name: "", scopes: [] }, webhook: { url: "not a url", events: [] } }
    assert_response :unprocessable_entity
    assert_equal 0, ApiToken.count
  end

  test "revoking an integration stops its token and webhook" do
    integration = ApiToken.create!(name: "Redmine", kind: "integration", user: @admin, scopes: %w[read], aircraft_ids: [ @a.id ])
    endpoint = integration.webhook_endpoints.create!(url: "https://redmine.example.com/", secret: "s" * 32, events: %w[squawk.created])
    sign_in @admin
    delete admin_integration_path(integration)
    assert integration.reload.revoked?
    assert_not endpoint.reload.enabled
  end

  test "integrations are for admins only" do
    sign_in @pilot
    get admin_integrations_path
    assert_redirected_to root_path
    post admin_integrations_path, params: { api_token: { name: "x", scopes: %w[read] } }
    assert_equal 0, ApiToken.count
  end

  test "the API reference is in the user guide" do
    sign_in @pilot
    get help_page_path("api")
    assert_response :success
    assert_select "h1", "REST API"
  end

  test "the suggested procedures describe the API once it's in use" do
    assert_no_match "API", ProceduresTemplates.hosting
    ApiToken.create!(name: "Redmine", kind: "integration", user: @admin, scopes: %w[read], aircraft_ids: [ @a.id ])
    text = ProceduresTemplates.hosting
    assert_match "The following programs are connected: Redmine.", text
    assert_match "cannot sign an entry", text
  end
end

require "test_helper"

class SsoTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  SSO_ENV = { "OIDC_ISSUER" => "https://auth.example.com/application/o/sam/", "OIDC_CLIENT_ID" => "sam", "OIDC_PROVIDER_NAME" => "Authentik" }.freeze
  KEYS = SSO_ENV.keys + %w[OIDC_AUTO_CREATE_USERS OIDC_TRUST_EMAIL OIDC_ADMIN_GROUP PASSWORD_LOGIN]

  setup do
    @saved = KEYS.to_h { [ _1, ENV[_1] ] }
    SSO_ENV.each { ENV[_1] = _2 }
    OmniAuth.config.test_mode = true
    @user = create_user("jane@example.com")
  end

  teardown do
    @saved.each { ENV[_1] = _2 }
    OmniAuth.config.mock_auth[:oidc] = nil
    OmniAuth.config.test_mode = false
  end

  def mock(uid: "sub-1", email: "jane@example.com", verified: true, groups: nil, name: "Jane Pilot")
    raw = { "email_verified" => verified }
    raw["groups"] = groups if groups
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(provider: "oidc", uid: uid, info: { email: email, name: name }, extra: { raw_info: raw })
  end

  def sso_sign_in
    post "/auth/oidc"
    follow_redirect! # to the callback
  end

  test "sign-in page offers SSO; a verified email links the existing account" do
    get new_session_path
    assert_select "form[action='/auth/oidc'] button", text: "Sign in with Authentik"
    assert_select "input[name=password]" # password sign-in still on

    mock
    sso_sign_in
    assert_redirected_to root_url
    assert_equal "sub-1", @user.reload.sso_uid
    follow_redirect!
    assert_response :success

    delete session_path
    mock(email: "changed@example.com") # matched by subject id from now on
    sso_sign_in
    assert_redirected_to root_url
  end

  test "an unverified email doesn't link (unless trusted) and nobody is created by default" do
    mock(verified: false)
    sso_sign_in
    assert_redirected_to new_session_path
    assert_match "There's no account for jane@example.com", flash[:alert]
    assert_nil @user.reload.sso_uid

    ENV["OIDC_TRUST_EMAIL"] = "true"
    sso_sign_in
    assert_redirected_to root_url
    assert_equal "sub-1", @user.reload.sso_uid
  end

  test "auto-created users start with no aircraft; admin group is synced only when groups are sent" do
    ENV["OIDC_AUTO_CREATE_USERS"] = "true"
    ENV["OIDC_ADMIN_GROUP"] = "sam-admins"
    mock(uid: "sub-2", email: "new@example.com", groups: [ "sam-admins" ])
    assert_difference -> { User.count } do
      sso_sign_in
    end
    created = User.find_by!(email_address: "new@example.com")
    assert_equal [ "sub-2", "Jane Pilot", true ], [ created.sso_uid, created.name, created.admin? ]
    assert_empty created.aircraft_roles

    delete session_path
    mock(uid: "sub-2", email: "new@example.com") # no groups claim: leave admin alone
    sso_sign_in
    assert created.reload.admin?
    delete session_path
    mock(uid: "sub-2", email: "new@example.com", groups: [ "pilots" ])
    sso_sign_in
    refute created.reload.admin?
  end

  test "linking and unlinking from the profile" do
    sign_in @user
    get edit_profile_path
    assert_select "form[action='/auth/oidc'] button", text: "Link Authentik"
    mock(uid: "sub-9", email: "someone-else@example.com", verified: false)
    sso_sign_in
    assert_redirected_to edit_profile_path
    assert_equal "sub-9", @user.reload.sso_uid

    other = create_user("other@example.com")
    sign_in other
    sso_sign_in
    assert_match "already linked to another user", flash[:alert]
    assert_nil other.reload.sso_uid

    sign_in @user
    delete sso_link_path
    assert_nil @user.reload.sso_uid
  end

  test "password sign-in can be turned off" do
    ENV["PASSWORD_LOGIN"] = "false"
    get new_session_path
    assert_select "input[name=password]", 0
    post session_path, params: { email_address: "jane@example.com", password: "test-password-123" }
    assert_redirected_to new_session_path
    assert_match "Sign in with Authentik", flash[:alert]
    post passwords_path, params: { email_address: "jane@example.com" }
    assert_redirected_to new_session_path
    assert_enqueued_emails 0

    sign_in_attempt = -> { mock; sso_sign_in }
    sign_in_attempt.()
    assert_redirected_to root_url
    delete sso_link_path
    assert_match "would lock you out", flash[:alert]
  end

  test "failures and a disabled provider" do
    get "/auth/failure", params: { message: "invalid_credentials" }
    assert_redirected_to new_session_path
    assert_equal "Authentik sign-in failed (invalid credentials).", flash[:alert]

    ENV["OIDC_ISSUER"] = nil
    get new_session_path
    assert_select "form[action='/auth/oidc']", 0
    get "/auth/oidc/callback"
    assert_response :not_found
  end
end

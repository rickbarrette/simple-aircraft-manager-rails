require "test_helper"

class SecurityHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user("jane@example.com")
  end

  test "changing email or password needs the current password" do
    sign_in @user
    patch profile_path, params: { user: { name: "Jane", email_address: "evil@example.com" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "Enter your current password"
    assert_equal "jane@example.com", @user.reload.email_address

    patch profile_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1", current_password: "wrong" } }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate("test-password-123")

    patch profile_path, params: { user: { name: "Jane Pilot", email_address: "jane@example.com" } } # no sensitive change
    assert_redirected_to root_path
    assert_equal "Jane Pilot", @user.reload.name

    patch profile_path, params: { user: { email_address: "jane2@example.com", current_password: "test-password-123" } }
    assert_redirected_to root_path
    assert_equal "jane2@example.com", @user.reload.email_address
  end

  test "a new password signs out other sessions; so does the button" do
    other = open_session
    other.post session_path, params: { email_address: @user.email_address, password: "test-password-123" }
    sign_in @user
    assert_equal 2, @user.sessions.count

    patch profile_path, params: { user: { password: "newpassword1", password_confirmation: "newpassword1", current_password: "test-password-123" } }
    assert_redirected_to root_path
    assert_equal 1, @user.sessions.count
    other.get root_path
    other.assert_redirected_to new_session_path

    other.post session_path, params: { email_address: @user.email_address, password: "newpassword1" }
    get edit_profile_path
    assert_select "button", text: "Sign out everywhere else"
    delete other_sessions_path
    assert_equal "Signed out 1 other session.", flash[:notice]
    assert_equal 1, @user.sessions.count
  end

  test "a password reset signs out every session; a blank password is refused" do
    sign_in @user
    token = @user.password_reset_token
    put password_path(token), params: { password: "brandnew9999", password_confirmation: "brandnew9999" }
    assert_redirected_to new_session_path
    assert_equal 0, @user.sessions.count

    put password_path(@user.reload.password_reset_token), params: { password: "", password_confirmation: "" }
    assert_redirected_to %r{/passwords/.+/edit}
  end

  test "idle sessions expire" do
    sign_in @user
    @user.sessions.update_all(updated_at: 31.days.ago)
    get root_path
    assert_redirected_to new_session_path
    assert_equal 0, @user.sessions.count

    sign_in @user
    @user.sessions.update_all(updated_at: 2.hours.ago)
    get root_path
    assert_response :success
    assert_in_delta Time.current, @user.sessions.sole.updated_at, 5
  end

  test "a squawk can't point at another aircraft's component" do
    a = create_aircraft(owner: @user)
    mine = create_component(a)
    elsewhere = create_component(create_aircraft)
    sign_in @user
    post aircraft_squawks_path(a), params: { squawk: { priority: 1, issue_reported: "Leak", component_id: elsewhere.id } }
    assert_nil a.squawks.last.component_id
    post aircraft_squawks_path(a), params: { squawk: { priority: 1, issue_reported: "Leak", component_id: mine.id } }
    assert_equal mine, a.squawks.last.component
  end

  test "pages send a strict CSP with a nonce on inline scripts" do
    sign_in @user
    get root_path
    csp = response.headers["Content-Security-Policy"]
    assert_match "script-src 'self' 'nonce-", csp
    assert_match "object-src 'none'", csp
    assert_match "frame-ancestors 'self'", csp
    nonce = csp[/'nonce-([^']+)'/, 1]
    assert_select "script:not([src])" do |scripts|
      scripts.each { assert_equal nonce, _1["nonce"], "inline script without the nonce: #{_1.to_html.truncate(80)}" }
    end
    assert_match "camera=()", response.headers["Permissions-Policy"]
    assert_equal "same-origin", response.headers["Cross-Origin-Opener-Policy"]
  end

  test "no inline event handlers left in views" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].select { File.read(_1).match?(/\son(click|change|input|submit|load)\s*[=:]/) }
    assert_empty offenders.map { _1.delete_prefix("#{Rails.root}/") }
  end

  test "file links expire" do
    a = create_aircraft(owner: @user)
    doc = a.documents.create!(name: "W&B", doc_type: "OTHER", pages: [ { io: StringIO.new("%PDF"), filename: "wb.pdf", content_type: "application/pdf" } ])
    path = Rails.application.routes.url_helpers.rails_blob_path(doc.pages.first, only_path: true)
    get path
    assert_response :redirect
    travel 2.hours do
      get path
      assert_response :not_found
    end
  end
end

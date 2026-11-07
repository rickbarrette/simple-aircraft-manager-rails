require "test_helper"

class EmailSignInTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { @user = create_user("jane@example.com") }

  def link_from_email
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "jane@example.com" ], mail.to
    mail.text_part.body.to_s[%r{http://example\.com(/session/link/[^\s]+)}, 1]
  end

  test "request a link, confirm, signed in; the link works once" do
    get new_session_path
    assert_select "a[href='#{new_sign_in_link_path}']", text: "Email me a sign-in link"

    post sign_in_links_path, params: { email_address: "Jane@Example.com " }
    assert_redirected_to new_session_path
    assert_match "If there's an account for that address", flash[:notice]
    path = link_from_email

    get path # opening the link (or a mail scanner) doesn't sign in
    assert_response :success
    assert_select "button", text: "Sign in"
    assert_equal 0, @user.sessions.count

    post "#{path}/consume"
    assert_redirected_to root_path
    assert_equal 1, @user.sessions.count
    follow_redirect!
    assert_response :success

    delete session_path
    get path
    assert_redirected_to new_sign_in_link_path
    assert_match "expired or was already used", flash[:alert]
    post "#{path}/consume"
    assert_redirected_to new_sign_in_link_path
    assert_equal 0, @user.reload.sessions.count
  end

  test "links expire, unknown addresses look the same, and it's off when password sign-in is" do
    post sign_in_links_path, params: { email_address: "jane@example.com" }
    path = link_from_email
    travel 16.minutes do
      post "#{path}/consume"
      assert_redirected_to new_sign_in_link_path
    end

    ActionMailer::Base.deliveries.clear
    post sign_in_links_path, params: { email_address: "nobody@example.com" }
    assert_match "If there's an account for that address", flash[:notice]
    perform_enqueued_jobs
    assert_empty ActionMailer::Base.deliveries

    get sign_in_link_path("forged-token")
    assert_redirected_to new_sign_in_link_path

    saved = %w[OIDC_ISSUER OIDC_CLIENT_ID PASSWORD_LOGIN].to_h { [ _1, ENV[_1] ] }
    ENV.update("OIDC_ISSUER" => "https://auth.example.com/", "OIDC_CLIENT_ID" => "sam", "PASSWORD_LOGIN" => "false")
    post sign_in_links_path, params: { email_address: "jane@example.com" }
    assert_redirected_to new_session_path
    assert_enqueued_emails 0
  ensure
    saved&.each { ENV[_1] = _2 }
  end

  test "admins can send a test email and see failures" do
    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    get admin_about_path
    assert_select "form[action='#{admin_test_email_path}'] button", text: "Send test email"

    assert_emails 1 do
      post admin_test_email_path
    end
    assert_redirected_to admin_about_path
    assert_equal "Test email sent to admin@example.com. If it doesn't arrive, check the spam folder.", flash[:notice]
    assert_equal "Test email from Simple Aircraft Manager", ActionMailer::Base.deliveries.last.subject

    failing = Class.new do
      def initialize(*) = nil
      def deliver!(*) = raise(Net::SMTPAuthenticationError.new(nil, message: "535 bad credentials"))
    end
    ActionMailer::Base.add_delivery_method :failing, failing
    AdminMailer.delivery_method = :failing
    begin
      post admin_test_email_path
    ensure
      AdminMailer.delivery_method = :test
    end
    assert_match "Sending failed: SMTPAuthenticationError", flash[:alert]

    sign_in @user
    post admin_test_email_path
    assert_redirected_to root_path
  end
end

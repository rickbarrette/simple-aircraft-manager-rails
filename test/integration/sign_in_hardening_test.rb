require "test_helper"

# Account lockout, password rules, and authenticator-app two-factor.
class SignInHardeningTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  PASSWORD = "test-password-123"

  setup do
    @user = create_user("jane@example.com")
  end

  def attempt(password, email: @user.email_address)
    post session_path, params: { email_address: email, password: password }
  end

  def totp(user, at: Time.current) = ROTP::TOTP.new(user.reload.otp_secret).at(at)

  def enable_two_factor(user)
    user.enable_otp!(User.new_otp_secret)
  end

  test "ten failed sign-ins lock the account for 15 minutes, even with the right password, and email the user" do
    assert_enqueued_emails(1) { 10.times { attempt("wrong-password") } }
    assert @user.reload.locked?
    attempt(PASSWORD)
    assert_redirected_to new_session_path(email_address: @user.email_address)
    assert_includes flash[:alert], "locked for 15 minutes"
    attempt("whatever", email: "nobody@example.com")
    assert_includes flash[:alert], "Try another email address or password" # same answer for unknown accounts

    travel 16.minutes do
      attempt(PASSWORD)
      assert_redirected_to root_url
      assert_equal 0, @user.reload.failed_sign_ins
    end
  end

  test "a successful sign-in resets the count; admins can unlock" do
    5.times { attempt("wrong-password") }
    attempt(PASSWORD)
    assert_equal 0, @user.reload.failed_sign_ins
    @user.update_columns(locked_until: 10.minutes.from_now)
    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    get admin_users_path
    assert_select ".badge-red", "Locked"
    patch unlock_admin_user_path(@user)
    refute @user.reload.locked?
  end

  test "passwords need 12 characters and mustn't be known from a breach" do
    sign_in @user
    patch profile_path, params: { user: { password: "short-pw1", password_confirmation: "short-pw1", current_password: PASSWORD } }
    assert_response :unprocessable_entity
    assert_includes response.body, "too short (minimum is 12 characters)"
    patch profile_path, params: { user: { password: "breached-password-1", password_confirmation: "breached-password-1", current_password: PASSWORD } }
    assert_response :unprocessable_entity
    assert_includes response.body, "data breach"
    patch profile_path, params: { user: { password: "a-good-new-password", password_confirmation: "a-good-new-password", current_password: PASSWORD } }
    assert_redirected_to root_path
    assert @user.reload.authenticate("a-good-new-password")
  end

  test "the breach check sends only a hash prefix and allows the password if the service is down" do
    checker = PwnedPasswords.checker
    PwnedPasswords.checker = ->(pw) { PwnedPasswords.lookup(pw) }
    sha1 = Digest::SHA1.hexdigest("correct horse battery").upcase
    stub_request(:get, "https://api.pwnedpasswords.com/range/#{sha1[0, 5]}").with(headers: { "Add-Padding" => "true" })
      .to_return(body: "0000000000000000000000000000000000A:0\r\n#{sha1[5..]}:42\r\n")
    assert PwnedPasswords.breached?("correct horse battery")
    stub_request(:get, %r{api\.pwnedpasswords\.com}).to_timeout
    refute PwnedPasswords.breached?("another long password")
  ensure
    PwnedPasswords.checker = checker
  end

  test "setting up an authenticator: scan, confirm with a code, get recovery codes" do
    sign_in @user
    get new_two_factor_path
    assert_select "img[src^='data:image/svg+xml;base64,']"
    secret = response.body[%r{<code class="break-all">([A-Z2-7 ]+)</code>}, 1].delete(" ")
    post two_factor_path, params: { code: "000000" }
    assert_redirected_to new_two_factor_path
    refute @user.reload.otp_enabled?
    post two_factor_path, params: { code: ROTP::TOTP.new(secret).now }
    assert_response :success
    assert_select "ul li", User::RECOVERY_CODES
    assert @user.reload.otp_enabled?
    assert_equal secret, @user.otp_secret
    assert_not_equal secret, @user.read_attribute_before_type_cast(:otp_secret) # encrypted
  end

  test "with two-factor on, sign-in asks for a code; codes work once; recovery codes work once" do
    codes = enable_two_factor(@user)
    attempt(PASSWORD)
    assert_redirected_to two_factor_session_path
    get root_path
    assert_redirected_to new_session_path # not signed in yet

    post two_factor_session_path, params: { code: "123456" }
    assert_redirected_to two_factor_session_path
    assert_equal 1, @user.reload.failed_sign_ins
    code = totp(@user)
    post two_factor_session_path, params: { code: code }
    assert_redirected_to root_url
    get root_path
    assert_response :success

    delete session_path
    attempt(PASSWORD)
    post two_factor_session_path, params: { code: code } # same code again: refused
    assert_redirected_to two_factor_session_path
    post two_factor_session_path, params: { code: codes.first.upcase }
    assert_redirected_to root_url
    assert_equal User::RECOVERY_CODES - 1, @user.reload.recovery_codes_left

    delete session_path
    attempt(PASSWORD)
    post two_factor_session_path, params: { code: codes.first }
    assert_redirected_to two_factor_session_path
  end

  test "the code step expires, and an emailed sign-in link also needs the code" do
    enable_two_factor(@user)
    attempt(PASSWORD)
    travel 6.minutes do
      post two_factor_session_path, params: { code: totp(@user) }
      assert_redirected_to new_session_path
    end

    token = @user.generate_token_for(:email_sign_in)
    post consume_sign_in_link_path(token)
    assert_redirected_to two_factor_session_path
    post two_factor_session_path, params: { code: totp(@user) }
    assert_redirected_to root_url
  end

  test "turning it off or making new recovery codes needs a code; admins can reset it" do
    enable_two_factor(@user)
    attempt(PASSWORD)
    post two_factor_session_path, params: { code: totp(@user) }
    delete two_factor_path, params: { code: "000000" }
    assert @user.reload.otp_enabled?
    travel 31.seconds do
      post recovery_codes_two_factor_path, params: { code: totp(@user) }
      assert_select "ul li", User::RECOVERY_CODES
    end
    travel 61.seconds do
      delete two_factor_path, params: { code: totp(@user) }
      refute @user.reload.otp_enabled?
    end

    enable_two_factor(@user)
    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    patch reset_two_factor_admin_user_path(@user)
    refute @user.reload.otp_enabled?
  end

  test "signing an entry also needs the authenticator code, and wrong passwords count toward the lockout" do
    a = create_aircraft(owner: @user)
    entry = a.logbook_entries.create!(date: Date.current, entry_type: "MAINTENANCE", text: "Changed oil", aircraft_hours_at_entry: 1000)
    cert = @user.certificates.create!(kind: "AP", number: "7654321")
    enable_two_factor(@user)
    attempt(PASSWORD)
    post two_factor_session_path, params: { code: totp(@user) }

    post aircraft_logbook_entry_signature_path(a, entry), params: { certificate_id: cert.id, password: PASSWORD, confirm: "1" }
    assert_response :unprocessable_entity
    assert_includes response.body, "authenticator code"
    post aircraft_logbook_entry_signature_path(a, entry), params: { certificate_id: cert.id, password: "wrong-password", confirm: "1" }
    assert_equal 2, @user.reload.failed_sign_ins
    travel 31.seconds do
      post aircraft_logbook_entry_signature_path(a, entry), params: { certificate_id: cert.id, password: PASSWORD, otp_code: totp(@user), confirm: "1" }
      assert_equal "password_totp", entry.reload.signature.auth_method
      assert_equal 0, @user.reload.failed_sign_ins
    end
  end
end

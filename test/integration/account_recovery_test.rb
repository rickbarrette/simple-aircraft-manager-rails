require "test_helper"
require "rake"

# Account recovery from the command line (bin/rails users:*).
class AccountRecoveryTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@example.com", admin: true)
    Rails.application.load_tasks if Rake::Task.tasks.none? { _1.name == "users:list" }
  end

  def rake(name, *args, env: {})
    Rake::Task[name].reenable
    old = env.to_h { |k, _| [ k, ENV[k] ] }
    env.each { ENV[_1] = _2 }
    out, = capture_io { Rake::Task[name].invoke(*args) }
    out
  ensure
    old&.each { ENV[_1] = _2 }
  end

  test "reset a forgotten password: generated, shown once, unlocks and signs out" do
    sign_in @admin
    @admin.update_columns(locked_until: 10.minutes.from_now, failed_sign_ins: 3)
    out = rake("users:reset_password", "Admin@Example.com")
    password = out[/New password for \S+: (\S+)/, 1]
    assert_equal 23, password.size
    @admin.reload
    assert @admin.authenticate(password)
    refute @admin.locked?
    assert_equal 0, @admin.sessions.count

    rake("users:reset_password", "admin@example.com", env: { "PASSWORD" => "chosen-password-99" })
    assert @admin.reload.authenticate("chosen-password-99")
    assert_raises(AccountRecovery::Error) { AccountRecovery.reset_password!("admin@example.com", password: "short") }
    assert_raises(AccountRecovery::Error) { AccountRecovery.reset_password!("nobody@example.com") }
  end

  test "a printed sign-in link signs in once" do
    link = rake("users:sign_in_link", "admin@example.com").lines.first.strip
    path = URI(link).path
    assert_match %r{/session/link/}, path
    post "#{path}/consume"
    assert_redirected_to root_path
    post "#{path}/consume"
    assert_redirected_to new_sign_in_link_path # spent

    @admin.update!(disabled_at: Time.current)
    assert_raises(AccountRecovery::Error) { AccountRecovery.sign_in_link("admin@example.com") }
  end

  test "unlock, reset two-factor, enable, disable, make admin, list" do
    user = create_user("jane@example.com")
    user.update_columns(locked_until: 10.minutes.from_now)
    user.enable_otp!(User.new_otp_secret)
    listing = rake("users:list")
    assert_match(/jane@example\.com .*LOCKED 2FA/, listing)

    rake("users:unlock", "jane@example.com")
    refute user.reload.locked?
    rake("users:reset_two_factor", "jane@example.com")
    refute user.reload.otp_enabled?
    rake("users:disable", "jane@example.com")
    assert user.reload.disabled?
    rake("users:enable", "jane@example.com")
    refute user.reload.disabled?
    rake("users:make_admin", "jane@example.com")
    assert user.reload.admin?
  end

  test "create a new admin when none can sign in" do
    out = rake("users:create_admin", "new-admin@example.com", "Jane Pilot")
    user = User.find_by!(email_address: "new-admin@example.com")
    assert user.admin?
    assert_equal "Jane Pilot", user.name
    assert user.authenticate(out[/password: (\S+)/, 1])
    assert_raises(AccountRecovery::Error) { AccountRecovery.create_admin!("admin@example.com") }
  end
end

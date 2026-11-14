require "test_helper"

# Protections for an installation reachable from the internet with nothing in
# front of it: secret key strength, the setup code, the AirTrail address check
# and the allowed host names.
class InternetExposureTest < ActionDispatch::IntegrationTest
  test "a placeholder or short secret key is refused; one shorter than recommended is weak" do
    assert_equal :unsafe, SecretKeyCheck.strength("change-me")
    assert_equal :unsafe, SecretKeyCheck.strength("x")
    assert_equal :unsafe, SecretKeyCheck.strength("a" * 80)
    assert_equal :weak, SecretKeyCheck.strength(SecureRandom.hex(20))
    assert_equal :ok, SecretKeyCheck.strength(SecureRandom.hex(64))
  end

  test "the setup code is required, shown only in the log, and used up" do
    SetupCode.clear
    logged = capture_log { get new_setup_path }
    assert_match(/Setup code: #{Regexp.escape(SetupCode.current)}/, logged)
    assert_no_match SetupCode.current, response.body
  end

  test "AirTrail can't be pointed at the server itself or link-local addresses, nor the private network by non-admins" do
    { "http://127.0.0.1:8080" => :never, "http://169.254.169.254" => :never, "http://[::1]" => :never,
      "http://10.0.0.5" => :private, "http://192.168.1.20:3000" => :private, "http://100.100.1.1" => :private }.each do |url, reason|
      error = assert_raises(AirTrailClient::BlockedAddress, url) { AirTrailClient.new(base_url: url, api_key: "k").me }
      assert_match(reason == :never ? "link-local" : "private network", error.message)
    end
  end

  test "admins and listed hosts may use private addresses, but never the server itself" do
    stub_request(:get, "http://192.168.1.20:3000/api/v1/me").to_return(status: 200, body: { data: { username: "u" } }.to_json)
    assert_equal "u", AirTrailClient.new(base_url: "http://192.168.1.20:3000", api_key: "k", allow_private: true).me["username"]
    assert_raises(AirTrailClient::BlockedAddress) { AirTrailClient.new(base_url: "http://127.0.0.1", api_key: "k", allow_private: true).me }

    with_env("AIRTRAIL_ALLOWED_HOSTS" => "airtrail.lan") do
      resolving_to("192.168.1.30") do
        stub_request(:get, "http://airtrail.lan/api/v1/me").to_return(status: 200, body: { data: { username: "v" } }.to_json)
        assert_equal "v", AirTrailClient.new(base_url: "http://airtrail.lan", api_key: "k").me["username"]
      end
    end
  end

  test "a name that resolves to a private address is checked by its address" do
    resolving_to("203.0.113.5", "10.1.2.3") do
      assert_raises(AirTrailClient::BlockedAddress) { AirTrailClient.new(base_url: "https://rebind.example.com", api_key: "k").me }
    end
  end

  test "a non-admin's connection to a private address is refused with a reason" do
    pilot = create_user
    sign_in pilot
    post air_trail_connection_path, params: { air_trail_connection: { base_url: "http://192.168.1.20", api_key: "k" } }
    follow_redirect! if response.redirect?
    assert_match "private network", flash[:alert].to_s + response.body
  end

  private

  def resolving_to(*ips)
    old = AirTrailClient.resolver
    AirTrailClient.resolver = ->(_) { ips }
    yield
  ensure
    AirTrailClient.resolver = old
  end

  def with_env(vars)
    old = vars.keys.to_h { [ _1, ENV[_1] ] }
    vars.each { ENV[_1] = _2 }
    yield
  ensure
    old.each { ENV[_1] = _2 }
  end

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    old, Rails.logger = Rails.logger, logger
    yield
    io.string
  ensure
    Rails.logger = old
  end
end

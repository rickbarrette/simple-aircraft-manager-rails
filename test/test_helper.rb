ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)
Dir[File.expand_path("support/**/*.rb", __dir__)].each { require _1 }
PwnedPasswords.checker = ->(password) { password == "breached-password-1" } # no network in tests
# No DNS in tests: names resolve to a public address, IP addresses to themselves.
AirTrailClient.resolver = ->(host) { host.match?(/\A[\d.]+\z|:/) ? [ host.delete("[]") ] : [ "203.0.113.10" ] }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    def create_user(email = "user#{SecureRandom.hex(3)}@example.com", admin: false)
      User.create!(email_address: email, password: "test-password-123", name: email.split("@").first, admin: admin)
    end

    def create_aircraft(owner: nil, pilot: nil, **attrs)
      Aircraft.create!({ tail_number: "N#{rand(10000..99999)}", tach_time: 1000 }.merge(attrs)).tap do |a|
        a.roles.create!(user: owner, role: "owner") if owner
        a.roles.create!(user: pilot, role: "pilot") if pilot
      end
    end

    def component_type(name = "Engine")
      ComponentType.find_or_create_by!(name: name)
    end

    def create_component(aircraft, **attrs)
      aircraft.components.create!({ component_type: component_type, manufacturer: "Lycoming", model: "O-320",
                                    status: "IN-USE", date_in_service: 1.year.ago.to_date }.merge(attrs))
    end
  end
end

class ActionDispatch::IntegrationTest
  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "test-password-123" }
    follow_redirect!
  end
end

require "net/http"

# Checks a password against the Have I Been Pwned breach corpus with the
# k-anonymity range API: only the first 5 characters of its SHA-1 are sent,
# never the password. If the service can't be reached the password is
# allowed (logged), so an outage doesn't stop anyone changing a password.
# PWNED_PASSWORDS_CHECK=false turns it off (e.g. no outbound internet).
module PwnedPasswords
  API = "https://api.pwnedpasswords.com/range/".freeze

  mattr_accessor :checker, default: ->(password) { lookup(password) }

  def self.enabled? = ENV["PWNED_PASSWORDS_CHECK"] != "false"
  def self.breached?(password) = enabled? && password.present? && checker.call(password)

  def self.lookup(password)
    sha1 = Digest::SHA1.hexdigest(password).upcase
    prefix, suffix = sha1[0, 5], sha1[5..]
    uri = URI("#{API}#{prefix}")
    req = Net::HTTP::Get.new(uri)
    req["Add-Padding"] = "true"
    req["User-Agent"] = "Simple-Aircraft-Manager"
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) { _1.request(req) }
    return false unless res.is_a?(Net::HTTPSuccess)
    res.body.each_line.any? do |line|
      hash, count = line.strip.split(":")
      hash == suffix && count.to_i.positive?
    end
  rescue StandardError => e
    Rails.logger.warn("[pwned passwords] check skipped: #{e.class}: #{e.message}")
    false
  end
end

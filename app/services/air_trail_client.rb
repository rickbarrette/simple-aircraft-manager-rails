require "net/http"

# Minimal client for AirTrail's REST API (/api/v1, Bearer API key).
class AirTrailClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(message, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end
  end
  class NetworkError < Error; end     # retryable: timeouts, connection refused, 5xx
  class AuthError < Error; end        # 401/403: bad key or missing scope
  class NotFound < Error; end
  class ValidationError < Error; end  # 400/422

  # An address the server won't send to (see #address). Like a bad key, the
  # user has to fix the connection, so it's recorded there and not retried.
  class BlockedAddress < AuthError; end

  # allow_private: may reach addresses on the private network (admins; and
  # hosts listed in AIRTRAIL_ALLOWED_HOSTS for everyone). The server itself
  # and link-local addresses (cloud metadata) are never reached.
  def initialize(base_url:, api_key:, timeout: 20, allow_private: false)
    @base = URI.parse(base_url.to_s.chomp("/"))
    @api_key = api_key
    @timeout = timeout
    @allow_private = allow_private || self.class.allowed_hosts.include?(@base.host.to_s.downcase)
  end

  # Host name → IP addresses (replaceable in tests, which have no DNS).
  class_attribute :resolver, default: ->(host) { Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address) }

  def self.allowed_hosts = ENV.fetch("AIRTRAIL_ALLOWED_HOSTS", "").split(",").map { _1.strip.downcase }.compact_blank

  def me = request(:get, "/api/v1/me").fetch("data")

  def search_airports(query) = request(:get, "/api/v1/airports", query: { query: query }).fetch("data")
  def search_aircraft(query) = request(:get, "/api/v1/aircraft", query: { query: query }).fetch("data")

  # Yields every flight the key's user owns (follows cursor pagination).
  def each_flight
    cursor = nil
    loop do
      q = { scope: "mine", limit: 100 }
      q[:cursor] = cursor if cursor
      page = request(:get, "/api/v1/flights", query: q)
      page.fetch("data").each { yield _1 }
      cursor = page.dig("page", "nextCursor")
      break unless cursor
    end
  end

  def create_flight(body) = request(:post, "/api/v1/flights", body: body).dig("data", "id")
  def update_flight(id, body) = request(:put, "/api/v1/flights/#{Integer(id)}", body: body)

  def delete_flight(id)
    request(:delete, "/api/v1/flights/#{Integer(id)}")
  rescue NotFound
    nil # already gone
  end

  private

  def request(method, path, query: nil, body: nil)
    uri = @base.dup
    uri.path = "#{@base.path}#{path}"
    uri.query = URI.encode_www_form(query) if query
    req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
    req["Authorization"] = "Bearer #{@api_key}"
    req["Accept"] = "application/json"
    if body
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = address(uri.host) # connect to the address that was checked (the name can't be re-pointed in between)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = http.read_timeout = @timeout
    handle(http.start { _1.request(req) })
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError => e
    raise NetworkError, I18n.t("services.air_trail.can_t_reach_airtrail_at", host: @base.host, message: e.message)
  end

  # The address to connect to: the host's first, once all of its addresses are
  # ones this connection may reach.
  def address(host)
    ips = resolver.call(host).map { IPAddr.new(_1.sub(/%.*/, "")) }.uniq
    raise SocketError, "no address" if ips.empty?
    ips.each do |ip|
      ip = ip.native # ::ffff:10.0.0.1 → 10.0.0.1
      reason = if ip.loopback? || ip.link_local? || UNREACHABLE.any? { _1.include?(ip) } then :never
      elsif (ip.private? || CGNAT.include?(ip)) && !@allow_private then :private
      end
      raise BlockedAddress, I18n.t("services.air_trail.blocked_#{reason}", host: host) if reason
    end
    ips.first.to_s
  end

  UNREACHABLE = [ IPAddr.new("0.0.0.0/8"), IPAddr.new("::/128"), IPAddr.new("224.0.0.0/4"), IPAddr.new("ff00::/8") ].freeze
  CGNAT = IPAddr.new("100.64.0.0/10") # shared address space, e.g. Tailscale

  def handle(response)
    status = response.code.to_i
    json = begin
      response.body.to_s.empty? ? {} : JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end
    return json if status.between?(200, 299)

    error = json["error"].is_a?(Hash) ? json["error"] : {}
    message = [ error["message"] || "HTTP #{status}", details(error["details"]) ].compact.join(": ")
    klass = case status
    when 401, 403 then AuthError
    when 404 then NotFound
    when 400, 409, 422 then ValidationError
    else NetworkError
    end
    raise klass.new("AirTrail: #{message}", status: status, code: error["code"])
  end

  def details(list)
    return nil unless list.is_a?(Array) && list.any?
    list.first(3).map { |d| [ Array(d["path"]).join("."), d["message"] ].compact_blank.join(" ") }.join("; ")
  end
end

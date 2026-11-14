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

  def initialize(base_url:, api_key:, timeout: 20)
    @base = URI.parse(base_url.to_s.chomp("/"))
    @api_key = api_key
    @timeout = timeout
  end

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

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                   open_timeout: @timeout, read_timeout: @timeout) { _1.request(req) }
    handle(response)
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError => e
    raise NetworkError, I18n.t("services.air_trail.can_t_reach_airtrail_at", host: @base.host, message: e.message)
  end

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

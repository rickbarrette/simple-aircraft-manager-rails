# In-memory AirTrail API for tests (WebMock). Mirrors /api/v1 shapes from
# AirTrail's openapi.yaml: { data: ... } envelopes, cursor pagination,
# Bearer auth and { error: { code, message } } errors.
class FakeAirTrail
  BASE = "https://airtrail.test".freeze
  AIRPORTS = {
    "KOQU" => 101, "KBID" => 102, "KPVD" => 103, "KMFD" => 104, "K1B9" => 105, "NH53" => 106
  }.freeze

  attr_reader :flights, :requests
  attr_accessor :scopes, :valid_key

  def initialize(test)
    @test = test
    @flights = {}
    @next_id = 1000
    @requests = []
    @scopes = AirTrailConnection::REQUIRED_SCOPES.dup
    @valid_key = "at_secret"
    stub!
  end

  def add_existing(date:, from:, to:, reg: "N12345", flight_number: nil, duration: nil)
    id = (@next_id += 1)
    @flights[id] = { "id" => id, "date" => date, "from" => airport(from), "to" => airport(to),
                     "flightNumber" => flight_number, "aircraftReg" => reg, "duration" => duration }
    id
  end

  private

  def airport(code) = { "id" => AIRPORTS.fetch(code), "icao" => code, "iata" => nil, "name" => "#{code} Airport" }

  def stub!
    @test.stub_request(:any, /airtrail\.test/).to_return do |req|
      @requests << [ req.method, req.uri.path, req.body.to_s.empty? ? nil : JSON.parse(req.body) ]
      next json(401, error: { code: "unauthorized", message: "Invalid API key" }) unless req.headers["Authorization"] == "Bearer #{@valid_key}"
      route(req)
    end
  end

  def route(req)
    path = req.uri.path
    query = URI.decode_www_form(req.uri.query.to_s).to_h
    case [ req.method, path ]
    in [ :get, "/api/v1/me" ]
      json(200, data: { id: "u-ricky", username: "ricky", displayName: "Ricky", role: nil, isOwner: true,
                        permissions: [], credential: { kind: "apiKey", scopes: @scopes } })
    in [ :get, "/api/v1/airports" ]
      code = query["query"].to_s.upcase
      json(200, data: AIRPORTS.key?(code) ? [ airport(code) ] : [], page: { nextCursor: nil })
    in [ :get, "/api/v1/aircraft" ]
      json(200, data: query["query"] == "C150" ? [ { id: 7, icao: "C150", name: "Cessna 150" } ] : [], page: { nextCursor: nil })
    in [ :get, "/api/v1/flights" ]
      all = @flights.values.sort_by { -_1["id"] }
      offset = query["cursor"].to_i
      page = all[offset, 2] || [] # tiny pages to exercise pagination
      json(200, data: page, page: { nextCursor: offset + 2 < all.size ? (offset + 2).to_s : nil })
    in [ :post, "/api/v1/flights" ]
      body = JSON.parse(req.body)
      return json(422, error: { code: "validation_failed", message: "Validation failed", details: [ { path: [ "fromId" ], message: "Required" } ] }) unless body["fromId"]
      id = (@next_id += 1)
      @flights[id] = body.merge("id" => id)
      json(201, data: { id: id })
    in [ :put, %r{\A/api/v1/flights/(\d+)\z} ]
      id = path[/\d+\z/].to_i
      return json(404, error: { code: "not_found", message: "Flight not found" }) unless @flights.key?(id)
      @flights[id] = JSON.parse(req.body).merge("id" => id)
      json(200, data: @flights[id])
    in [ :delete, %r{\A/api/v1/flights/(\d+)\z} ]
      id = path[/\d+\z/].to_i
      @flights.delete(id) ? { status: 204, body: "" } : json(404, error: { code: "not_found", message: "Flight not found" })
    else
      json(404, error: { code: "not_found", message: "No route" })
    end
  end

  def json(status, payload) = { status: status, body: JSON.generate(payload), headers: { "Content-Type" => "application/json" } }
end

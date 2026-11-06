# Pushes a user's flights to their AirTrail account through the REST API.
#
# - push(flight): create the AirTrail flight, or replace it (PUT) if it
#   changed since the last sync. Skips unchanged flights (payload digest).
# - backfill: link flights that already exist in AirTrail (e.g. from an
#   earlier file import) instead of duplicating them, then push the rest.
# - Airports are looked up by code once per connection and cached; codes
#   AirTrail doesn't know are recorded so the user can map them by hand.
class AirTrailSyncer
  class UnresolvedAirport < StandardError; end

  AIRPORT_RECHECK = 1.day

  def initialize(connection, client: connection.client)
    @connection = connection
    @client = client
    @aircraft_ids = {}
  end

  # Flights this connection mirrors: the ones its user logged.
  def flights = FlightLog.where(user_id: @connection.user_id)

  def ensure_identity!
    return if @connection.remote_user_id.present?
    me = @client.me
    @connection.update!(remote_user_id: me["id"], remote_username: me["username"], status: "ok",
                        last_error: nil, checked_at: Time.current)
  end

  def push(flight, leg: :lookup)
    ensure_identity!
    sync = @connection.syncs.find_or_initialize_by(flight_log: flight)
    body = payload(flight, leg: leg == :lookup ? AirTrailFlightData.leg_number(flight) : leg)
    digest = Digest::SHA256.hexdigest(JSON.generate(body))
    return sync if sync.remote_id && sync.status == "synced" && sync.payload_digest == digest

    if sync.remote_id
      begin
        @client.update_flight(sync.remote_id, body)
      rescue AirTrailClient::NotFound # deleted in AirTrail: recreate
        sync.remote_id = @client.create_flight(body)
      end
    else
      sync.remote_id = @client.create_flight(body)
    end
    sync.update!(status: "synced", payload_digest: digest, synced_at: Time.current, last_error: nil)
    sync
  rescue UnresolvedAirport, AirTrailClient::ValidationError => e
    sync&.update!(status: "error", last_error: e.message)
    sync
  rescue AirTrailClient::AuthError => e
    @connection.update!(status: "error", last_error: e.message, checked_at: Time.current)
    sync&.update!(status: "error", last_error: e.message)
    raise
  end

  def delete_remote(remote_id) = @client.delete_flight(remote_id)

  # Returns { linked:, pushed:, failed: }.
  def backfill
    ensure_identity!
    local = flights.includes(:aircraft).order(:date, :created_at, :id).to_a
    legs = AirTrailFlightData.leg_numbers(local)
    linked = link_existing(local, legs)
    pushed = 0
    failed = 0
    local.each do |f|
      next unless AirTrailFlightData.exportable?(f)
      sync = push(f, leg: legs[f.id])
      sync.status == "synced" ? pushed += 1 : failed += 1
    end
    @connection.update!(backfilled_at: Time.current, status: "ok", last_error: nil)
    { linked: linked, pushed: pushed, failed: failed }
  end

  def payload(flight, leg:)
    from = airport_id(flight.departure_location)
    to = airport_id(flight.destination_location)
    body = {
      date: flight.date.iso8601,
      datePrecision: "day",
      departure: nil,
      arrival: nil,
      duration: AirTrailFlightData.duration(flight),
      flightNumber: leg,
      aircraftReg: AirTrailFlightData.registration(flight.aircraft),
      note: AirTrailFlightData.note(flight),
      fromId: from,
      toId: to,
      aircraftId: aircraft_id(flight.aircraft.icao_type),
      airlineId: nil,
      passengers: [ { userId: @connection.remote_user_id, guestName: nil, seat: "pilot", seatNumber: nil,
                      seatClass: nil, flightReason: nil, customFields: {} } ],
      customFields: {}
    }
    track = AirTrailFlightData.track(flight)
    body[:track] = track if track
    body
  end

  # Look an airport code up in AirTrail (cached per connection).
  def airport_id(code)
    normalized = AirTrailFlightData.airport_code(code)
    raise UnresolvedAirport, "Airport “#{code.presence || '(blank)'}” isn't a code AirTrail can use" unless normalized

    cached = @connection.airports.find_or_initialize_by(code: normalized)
    fresh = cached.manual? || cached.remote_id || (cached.looked_up_at && cached.looked_up_at > AIRPORT_RECHECK.ago)
    unless fresh
      results = @client.search_airports(normalized)
      match = results.find { _1["icao"].to_s.casecmp?(normalized) } || results.find { _1["iata"].to_s.casecmp?(normalized) }
      cached.update!(remote_id: match&.dig("id"), remote_icao: match&.dig("icao"), looked_up_at: Time.current)
    end
    cached.remote_id or raise UnresolvedAirport, "AirTrail doesn't know airport #{normalized}. Map it on your AirTrail settings page"
  end

  # Map a code to an airport the user names (e.g. its ICAO/GPS code in AirTrail).
  def map_airport(code, airtrail_code)
    results = @client.search_airports(airtrail_code)
    match = results.find { _1["icao"].to_s.casecmp?(airtrail_code) || _1["iata"].to_s.casecmp?(airtrail_code) } || results.first
    return nil unless match
    @connection.airports.find_or_initialize_by(code: code)
               .update!(remote_id: match["id"], remote_icao: match["icao"], manual: true, looked_up_at: Time.current)
    match
  end

  private

  def aircraft_id(icao_type)
    return nil if icao_type.blank?
    @aircraft_ids.fetch(icao_type) do
      @aircraft_ids[icao_type] = @client.search_aircraft(icao_type).find { _1["icao"].to_s.casecmp?(icao_type) }&.dig("id")
    end
  end

  # Match local flights to AirTrail flights already there (same signature
  # AirTrail de-duplicates on), falling back to date + registration + leg +
  # duration when the airports were mapped differently. Learns airport ids
  # from matched flights so hand-mapped airports carry over.
  def link_existing(local, legs)
    already = @connection.syncs.where.not(remote_id: nil).pluck(:flight_log_id).to_set
    remote = []
    @client.each_flight { remote << _1 }
    taken = @connection.syncs.where.not(remote_id: nil).pluck(:remote_id).to_set
    remote.reject! { taken.include?(_1["id"]) }

    exact = remote.group_by { |r| [ r["date"], r.dig("from", "icao").to_s.upcase, r.dig("to", "icao").to_s.upcase, r["flightNumber"].to_s, r["aircraftReg"].to_s.upcase ] }
    loose = remote.group_by { |r| [ r["date"], r["aircraftReg"].to_s.upcase, r["flightNumber"].to_s, r["duration"] ] }
    used = Set.new
    linked = 0

    local.each do |f|
      next if already.include?(f.id) || !AirTrailFlightData.exportable?(f)
      reg = AirTrailFlightData.registration(f.aircraft).to_s
      leg = legs[f.id].to_s
      candidates = exact[[ f.date.iso8601, AirTrailFlightData.airport_code(f.departure_location),
                           AirTrailFlightData.airport_code(f.destination_location), leg, reg ]] || []
      candidates += loose[[ f.date.iso8601, reg, leg, AirTrailFlightData.duration(f) ]] || []
      match = candidates.find { !used.include?(_1["id"]) }
      next unless match

      used << match["id"]
      learn_airport(f.departure_location, match["from"])
      learn_airport(f.destination_location, match["to"])
      @connection.syncs.find_or_initialize_by(flight_log: f).update!(remote_id: match["id"], status: "pending")
      linked += 1
    end
    linked
  end

  def learn_airport(code, remote_airport)
    normalized = AirTrailFlightData.airport_code(code)
    return unless normalized && remote_airport.is_a?(Hash) && remote_airport["id"]
    cached = @connection.airports.find_or_initialize_by(code: normalized)
    return if cached.manual? || cached.remote_id
    cached.update!(remote_id: remote_airport["id"], remote_icao: remote_airport["icao"], looked_up_at: Time.current)
  end
end

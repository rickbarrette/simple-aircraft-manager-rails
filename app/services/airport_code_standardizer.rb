# Rewrites an aircraft's logged airport codes to the airport database's
# standard code (AirTrail's ICAO-style code, e.g. 1B9 → K1B9).
#
#   s = AirportCodeStandardizer.new(aircraft)
#   s.changes   # => [Change(from: "1B9", to: "K1B9", airport:, flights: 12, suggested: true), ...]
#   s.unknown   # => [Unknown(code: "0R8", flights: 2, suggestion: <08R Richmond Airport>)]
#   s.apply!(%w[1B9 44N], fixes: { "0R8" => "08R" })  # returns entries updated
class AirportCodeStandardizer
  Change = Struct.new(:from, :to, :airport, :flights, :suggested, :note, keyword_init: true)
  # A code not in the database, with a likely intended airport (e.g. a typo).
  Unknown = Struct.new(:code, :flights, :suggestion, keyword_init: true)

  def initialize(aircraft)
    @aircraft = aircraft
  end

  def changes
    analyze[:changes]
  end

  def unknown
    analyze[:unknown]
  end

  # codes: logged codes to standardize; fixes: { unknown code => airport code }
  # for codes not in the database (resolved to that airport's standard code).
  def apply!(codes, fixes: {})
    chosen = changes.select { codes.include?(_1.from) }
    known_unknown = unknown.map(&:code)
    fixes.each do |from, target|
      from = from.to_s.strip.upcase
      airport = Airport.lookup(target)
      next unless airport && known_unknown.include?(from)
      chosen << Change.new(from: from, to: airport.code, airport: airport)
    end
    updated = 0
    FlightLog.transaction do
      chosen.each do |c|
        updated += @aircraft.flight_logs.where(departure_location: c.from).update_all(departure_location: c.to, updated_at: Time.current)
        updated += @aircraft.flight_logs.where(destination_location: c.from).update_all(destination_location: c.to, updated_at: Time.current)
      end
      if chosen.any?
        @aircraft.log_event!("flight", "Standardized #{chosen.size} airport codes",
                             notes: chosen.map { "#{_1.from}→#{_1.to}" }.join(", "))
      end
    end
    updated
  end

  private

  def analyze
    @analyze ||= begin
      counts = Hash.new(0)
      @aircraft.flight_logs.pluck(:departure_location, :destination_location).flatten.each do |code|
        counts[code.to_s.strip.upcase] += 1 if code.present?
      end
      changes = []
      unknown = []
      counts.sort.each do |code, n|
        airport = Airport.lookup(code)
        if airport.nil?
          unknown << Unknown.new(code: code, flights: n, suggestion: suggest(code, counts.keys))
        elsif airport.code != code
          renamed = !airport.code.end_with?(code) # e.g. 4MB → K5M3, not just a K prefix
          note = if airport.kind == "closed" then "Closed airport. Check it's the right one"
          elsif renamed then "Different identifier, not just a prefix. Check it's the right field"
          end
          changes << Change.new(from: code, to: airport.code, airport: airport, flights: n,
                                suggested: airport.kind != "closed", note: note)
        end
      end
      { changes: changes, unknown: unknown }
    end
  end

  # Likely intended airport for an unknown code: the same characters in a
  # different order (e.g. 0R8 → 08R), preferring codes this aircraft has used.
  def suggest(code, logged_codes)
    return nil unless code.length.between?(3, 4)
    candidates = code.chars.permutation.map(&:join).uniq - [ code ]
    familiar = candidates & logged_codes
    (familiar + (candidates - familiar)).each do |candidate|
      airport = Airport.lookup(candidate)
      return airport if airport && airport.kind != "closed"
    end
    nil
  end
end

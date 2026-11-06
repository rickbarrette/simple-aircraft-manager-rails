# Flight details shared by the AirTrail file export and the API sync, so a
# flight looks the same in AirTrail whichever way it got there (and the sync
# can recognize flights that came in through a file import).
module AirTrailFlightData
  AIRPORT_FORMAT = /\A[A-Z0-9]{1,4}\z/

  module_function

  # The code AirTrail uses for a logged airport, or nil if AirTrail can't take
  # it. Logged codes are translated through the airport database (the same
  # OurAirports data AirTrail uses), e.g. 1B9 → K1B9, 4MB → K5M3.
  def airport_code(code)
    c = code.to_s.strip.upcase
    return nil if c.empty?
    translated = Airport.airtrail_code_for(c) || c
    translated if translated.match?(AIRPORT_FORMAT)
  end

  def exportable?(flight)
    airport_code(flight.departure_location) && airport_code(flight.destination_location)
  end

  # Seconds, from Hobbs time (or tach); nil for zero-time entries.
  def duration(flight)
    hours = (flight.hobbs_time || flight.tach_time).to_f
    hours.positive? ? (hours * 3600).round : nil
  end

  def note(flight)
    times = [ "Tach #{flight.tach_time} h", (flight.hobbs_time && "Hobbs #{flight.hobbs_time} h") ].compact.join(" · ")
    [ times, flight.route.presence, flight.notes.presence ].compact.join("\n").truncate(1000)
  end

  def registration(aircraft) = aircraft.tail_number.to_s.upcase.first(10).presence

  # AirTrail de-duplicates on date + airports + flight number (+ reg, times).
  # Repeat legs on the same day and route get "#2", "#3"… in log order.
  def leg_numbers(flights)
    seen = Hash.new(0)
    flights.to_h do |f|
      key = [ f.aircraft_id, f.date, airport_code(f.departure_location), airport_code(f.destination_location) ]
      seen[key] += 1
      [ f.id, (seen[key] > 1 ? "##{seen[key]}" : nil) ]
    end
  end

  def leg_number(flight)
    same_route = flight.aircraft.flight_logs.where(date: flight.date).order(:created_at, :id).select do |f|
      airport_code(f.departure_location) == airport_code(flight.departure_location) &&
        airport_code(f.destination_location) == airport_code(flight.destination_location)
    end
    leg_numbers(same_route)[flight.id]
  end

  # AirTrail TrackInput from the flight's track log, or nil.
  def track(flight)
    TrackParser.parse_attachment(flight.track_log)&.as_air_trail_json
  rescue TrackParser::Error, ActiveStorage::FileNotFoundError
    nil
  end
end

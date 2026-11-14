# Builds an AirTrail import file (Settings → Import → AirTrail in AirTrail,
# https://github.com/johanohly/AirTrail) from an aircraft's flight log.
#
# Format follows AirTrail's own backup schema (src/lib/import/airtrail.ts):
# { flights: [...], users: [...] }, with airports referenced by code
# (AirTrail asks the user to map codes it doesn't know) and the pilot as the
# single passenger in the "pilot" seat. AirTrail matches the exported user to
# a local account by username.
#
# AirTrail de-duplicates imports on date + airports + flight number +
# registration + departure/arrival times. Our flights have no times, so
# repeat legs on the same day and route get a stable leg number ("#2", "#3")
# in the flight-number field; re-exporting and re-importing is then safe.
class AirTrailExport
  USERNAME_FORMAT = /\A[A-Za-z0-9._-]{3,20}\z/
  TYPE_FORMAT = /\A[A-Z0-9]{1,4}\z/
  EXPORT_USER_ID = "sam-pilot".freeze

  attr_reader :errors

  def initialize(aircraft, username:, aircraft_type: nil, only_user: nil)
    @aircraft = aircraft
    @username = username.to_s.strip
    @aircraft_type = aircraft_type.to_s.strip.upcase.presence || aircraft.icao_type
    @only_user = only_user
    @errors = []
  end

  def valid?
    @errors = []
    @errors << I18n.t("services.air_trail.airtrail_username_must_be_3") unless @username.match?(USERNAME_FORMAT)
    @errors << I18n.t("services.air_trail.aircraft_type_must_be_an") if @aircraft_type && !@aircraft_type.match?(TYPE_FORMAT)
    @errors << I18n.t("services.air_trail.no_flights_to_export") if exportable.empty?
    @errors.empty?
  end

  def flights
    @flights ||= begin
      scope = @aircraft.flight_logs.includes(track_log_attachment: :blob).order(:date, :created_at, :id)
      scope = scope.where(user: @only_user) if @only_user
      scope.to_a
    end
  end

  # Flights need both airports, as codes AirTrail can look up.
  def exportable = @exportable ||= flights.select { AirTrailFlightData.exportable?(_1) }
  def skipped = flights.size - exportable.size

  def filename = "#{@aircraft.tail_number.parameterize}-airtrail-#{Date.current}.json"

  def to_json(*) = JSON.pretty_generate(as_json)

  def as_json(*)
    {
      flights: exportable.zip(leg_numbers).map { |f, leg| flight_json(f, leg) },
      users: [ { id: EXPORT_USER_ID, username: @username, displayName: @username } ]
    }
  end

  private

  def airport(code) = AirTrailFlightData.airport_code(code)

  def leg_numbers
    legs = AirTrailFlightData.leg_numbers(exportable)
    exportable.map { legs[_1.id] }
  end

  def flight_json(f, leg)
    json = {
      date: f.date.iso8601,
      datePrecision: "day",
      from: { code: airport(f.departure_location) },
      to: { code: airport(f.destination_location) },
      departure: nil,
      arrival: nil,
      duration: AirTrailFlightData.duration(f), # seconds
      airline: nil,
      aircraft: @aircraft_type && { name: aircraft_name, icao: @aircraft_type },
      flightNumber: leg,
      aircraftReg: AirTrailFlightData.registration(@aircraft),
      note: AirTrailFlightData.note(f),
      passengers: [
        { userId: EXPORT_USER_ID, guestName: nil, seat: "pilot", seatNumber: nil,
          seatClass: nil, flightReason: nil, customFields: {} }
      ]
    }
    track = AirTrailFlightData.track(f)
    json[:track] = track if track
    json
  end

  def aircraft_name
    [ @aircraft.make, @aircraft.model ].compact_blank.join(" ").presence || @aircraft_type
  end
end

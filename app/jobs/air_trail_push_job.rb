# Create/update one flight in its pilot's AirTrail account.
class AirTrailPushJob < ApplicationJob
  queue_as :default
  retry_on AirTrailClient::NetworkError, wait: :polynomially_longer, attempts: 6
  discard_on AirTrailClient::AuthError # recorded on the connection; user must fix the key

  def perform(flight_log_id)
    flight = FlightLog.includes(:aircraft, user: :air_trail_connection).find_by(id: flight_log_id) or return
    connection = flight.user&.air_trail_connection
    return unless connection&.enabled?
    return unless AirTrailFlightData.exportable?(flight)
    AirTrailSyncer.new(connection).push(flight)
  end
end

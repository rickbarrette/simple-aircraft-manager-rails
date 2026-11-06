# Sync all of a user's flights: link ones already in AirTrail, push the rest.
class AirTrailBackfillJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(connection_id) { "air_trail_backfill_#{connection_id}" } if respond_to?(:limits_concurrency)
  retry_on AirTrailClient::NetworkError, wait: :polynomially_longer, attempts: 3
  discard_on AirTrailClient::AuthError

  def perform(connection_id)
    connection = AirTrailConnection.find_by(id: connection_id) or return
    return unless connection.enabled?
    AirTrailSyncer.new(connection).backfill
  end
end

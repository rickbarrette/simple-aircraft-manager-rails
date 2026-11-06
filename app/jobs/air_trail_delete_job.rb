# Remove a deleted flight from AirTrail.
class AirTrailDeleteJob < ApplicationJob
  queue_as :default
  retry_on AirTrailClient::NetworkError, wait: :polynomially_longer, attempts: 6
  discard_on AirTrailClient::AuthError

  def perform(connection_id, remote_id)
    connection = AirTrailConnection.find_by(id: connection_id) or return
    return unless connection.enabled?
    AirTrailSyncer.new(connection).delete_remote(remote_id)
  end
end

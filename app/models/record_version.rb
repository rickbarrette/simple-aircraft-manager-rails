# One change to a maintenance record (create, update, destroy), kept for
# good (AC 120-78B 3.2.2). Each aircraft's versions form a hash chain:
# chain_hash = SHA-256(prev_hash + payload), so deleting, reordering or
# editing a version breaks the chain and the nightly check reports it.
class RecordVersion < ApplicationRecord
  belongs_to :user, optional: true

  scope :chronological, -> { order(:id) }

  before_update { throw :abort }
  before_destroy { throw :abort }

  def self.digest(prev_hash, payload) = OpenSSL::Digest::SHA256.hexdigest("#{prev_hash}\n#{payload}")

  def self.append!(item:, aircraft_id:, event:, changes:)
    now = Time.current
    payload = { "item_type" => item.class.name, "item_id" => item.id, "event" => event, "changes" => changes,
                "user_id" => Current.user&.id, "at" => now.utc.iso8601(6) }.to_json
    prev = where(aircraft_id: aircraft_id).order(:id).last&.chain_hash
    create!(aircraft_id: aircraft_id, item_type: item.class.name, item_id: item.id, event: event, user_id: Current.user&.id,
            ip_address: Current.ip_address, payload: payload, prev_hash: prev, chain_hash: digest(prev, payload), created_at: now)
  end

  def changes_hash = JSON.parse(payload)["changes"]

  # Field names changed by this version (for display).
  def changed_fields
    event == "update" ? changes_hash.keys : []
  end
end

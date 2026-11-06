# Cached AirTrail airport id for an airport code (remote_id nil = not found).
class AirTrailAirport < ApplicationRecord
  belongs_to :connection, class_name: "AirTrailConnection", foreign_key: :air_trail_connection_id
  normalizes :code, with: ->(c) { c.to_s.strip.upcase }
end

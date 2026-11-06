class AirTrailSync < ApplicationRecord
  belongs_to :connection, class_name: "AirTrailConnection", foreign_key: :air_trail_connection_id
  belongs_to :flight_log

  scope :failed, -> { where(status: "error") }
end

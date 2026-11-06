# A user's AirTrail account (https://github.com/johanohly/AirTrail). Flights
# the user logs are pushed there through AirTrail's REST API.
#
# The API key needs these scopes: profile.read, flight.read.own,
# flight.create.own, flight.update.own, flight.delete.own,
# reference_data.read and tracks.write.
class AirTrailConnection < ApplicationRecord
  REQUIRED_SCOPES = %w[profile.read flight.read.own flight.create.own flight.update.own
                       flight.delete.own reference_data.read tracks.write].freeze

  belongs_to :user
  has_many :syncs, class_name: "AirTrailSync", dependent: :delete_all
  has_many :airports, class_name: "AirTrailAirport", dependent: :delete_all

  encrypts :api_key

  normalizes :base_url, with: ->(url) { url.strip.chomp("/") }
  validates :base_url, presence: true, format: { with: %r{\Ahttps?://[^\s/]+(:\d+)?(/\S*)?\z}i, message: "must be a http(s) URL" }
  validates :api_key, presence: true

  scope :active, -> { where(enabled: true) }

  def client = AirTrailClient.new(base_url: base_url, api_key: api_key)

  def ok? = status == "ok"

  def unresolved_airport_codes
    airports.where(remote_id: nil).order(:code).pluck(:code)
  end

  def counts
    syncs.group(:status).count.reverse_merge("synced" => 0, "pending" => 0, "error" => 0)
  end
end

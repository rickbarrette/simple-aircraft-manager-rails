class FlightLog < ApplicationRecord
  include UploadValidation

  belongs_to :aircraft
  belongs_to :user, optional: true
  has_many :consumable_records, dependent: :nullify
  # Capture AirTrail ids before the sync rows are deleted, so the remote flights can be removed too.
  before_destroy :remember_air_trail_flights, prepend: true
  has_many :air_trail_syncs, dependent: :delete_all
  has_one_attached :track_log

  validates :date, presence: true
  validates :tach_time, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :hobbs_time, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates_uploads :track_log
  before_validation :derive_times
  normalizes :departure_location, :destination_location, with: ->(code) { code.strip.upcase.presence }
  after_commit :push_to_air_trail, on: %i[create update]
  after_commit :delete_from_air_trail, on: :destroy

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def route_summary
    [ departure_location, destination_location ].compact_blank.join(" → ")
  end

  private

  def push_to_air_trail
    AirTrailPushJob.perform_later(id) if user_id && AirTrailConnection.active.exists?(user_id: user_id)
  end

  def remember_air_trail_flights
    @air_trail_remote = air_trail_syncs.where.not(remote_id: nil).pluck(:air_trail_connection_id, :remote_id)
  end

  def delete_from_air_trail
    Array(@air_trail_remote).each { |connection_id, remote_id| AirTrailDeleteJob.perform_later(connection_id, remote_id) }
  end

  # Let the pilot enter out/in readings instead of the delta.
  def derive_times
    self.tach_time = tach_in - tach_out if tach_time.blank? && tach_in && tach_out
    self.hobbs_time = hobbs_in - hobbs_out if hobbs_time.blank? && hobbs_in && hobbs_out
  end
end

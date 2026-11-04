class FlightLog < ApplicationRecord
  include UploadValidation

  belongs_to :aircraft
  belongs_to :user, optional: true
  has_many :consumable_records, dependent: :nullify
  has_one_attached :track_log

  validates :date, presence: true
  validates :tach_time, presence: true, numericality: { greater_than: 0 }
  validates :hobbs_time, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates_uploads :track_log
  before_validation :derive_times

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def route_summary
    [ departure_location, destination_location ].compact_blank.join(" → ")
  end

  private

  # Let the pilot enter out/in readings instead of the delta.
  def derive_times
    self.tach_time = tach_in - tach_out if tach_time.blank? && tach_in && tach_out
    self.hobbs_time = hobbs_in - hobbs_out if hobbs_time.blank? && hobbs_in && hobbs_out
  end
end

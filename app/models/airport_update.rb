# One run of the OurAirports update (see AirportData / AirportUpdateJob).
class AirportUpdate < ApplicationRecord
  belongs_to :requested_by, class_name: "User", optional: true

  scope :recent_first, -> { order(created_at: :desc) }

  def self.in_progress = where(status: %w[queued running]).where(created_at: 2.hours.ago..)
  def self.last_success = where(status: "done").order(finished_at: :desc).first

  def failed? = status == "failed"
  def done? = status == "done"
  def in_progress? = status.in?(%w[queued running])

  def summary
    "#{created_count} added, #{updated_count} updated, #{removed_count} removed"
  end
end

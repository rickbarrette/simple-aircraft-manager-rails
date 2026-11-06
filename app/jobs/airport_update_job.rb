# Downloads OurAirports and syncs the airports table (AirportData.refresh!).
class AirportUpdateJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: "airport_update", duration: 1.hour if respond_to?(:limits_concurrency)

  def perform(update_id = nil)
    update = (update_id && AirportUpdate.find_by(id: update_id)) || AirportUpdate.create!(source_url: AirportData::SOURCE_URL)
    update.update!(status: "running", started_at: Time.current, error: nil)
    counts = AirportData.refresh!(update.source_url.presence || AirportData::SOURCE_URL)
    update.update!(status: "done", finished_at: Time.current, created_count: counts[:created],
                   updated_count: counts[:updated], removed_count: counts[:removed])
  rescue StandardError => e
    update&.update!(status: "failed", finished_at: Time.current, error: "#{e.class}: #{e.message}".truncate(1000))
    Rails.logger.error("[airports] update failed: #{e.class}: #{e.message}")
  end

  # Called at boot: populate the table on first start, like AirTrail does.
  def self.ensure_populated
    return if Airport.where(custom: false).exists? || AirportUpdate.in_progress.exists?
    update = AirportUpdate.create!(source_url: AirportData::SOURCE_URL)
    perform_later(update.id)
  end
end

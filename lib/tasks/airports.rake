namespace :airports do
  desc "Update airports from OurAirports now (same as Admin → Airports → Update)"
  task update: :environment do
    update = AirportUpdate.create!(source_url: AirportData::SOURCE_URL)
    AirportUpdateJob.perform_now(update.id)
    update.reload
    puts update.failed? ? "Failed: #{update.error}" : "Added #{update.created_count}, updated #{update.updated_count}, removed #{update.removed_count}"
  end
end

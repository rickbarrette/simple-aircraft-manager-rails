# Like AirTrail: when the server starts with no airport data, download it
# from OurAirports in the background. Admins can update it later from
# Admin → Airports.
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server)

  begin
    AirportUpdateJob.ensure_populated
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[airports] couldn't check airport data at boot: #{e.message}")
  end
end

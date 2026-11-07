# Record the running software version (Admin → About) once the app is up.
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server) || ENV["SOLID_QUEUE_IN_PUMA"]
  AppRevision.touch_current! if ActiveRecord::Base.connection.data_source_exists?("app_revisions")
rescue StandardError => e
  Rails.logger.warn("[app revisions] #{e.class}: #{e.message}")
end

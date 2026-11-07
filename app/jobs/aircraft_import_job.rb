# Imports a staged .sam.zip (see AircraftArchive::Importer) and records the outcome.
class AircraftImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = AircraftImport.find_by(id: import_id) or return
    return unless import.status == "queued"
    import.update!(status: "running", started_at: Time.current)

    result = import.archive.open do |file|
      AircraftArchive::Importer.new(file.path, owner: import.user, tail_number: import.tail_number,
                                               progress: ->(counts) { import.update_columns(counts: counts, updated_at: Time.current) }).run
    end
    import.update!(status: "done", finished_at: Time.current, aircraft: result[:aircraft],
                   counts: result[:counts], warnings: result[:warnings].first(200))
  rescue AircraftArchive::Error => e
    import&.update!(status: "failed", finished_at: Time.current, error: e.message)
  rescue StandardError => e
    import&.update!(status: "failed", finished_at: Time.current, error: "Import failed: #{e.class}: #{e.message}".truncate(1000))
    Rails.logger.error("[aircraft import] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
  ensure
    import&.archive&.purge_later if import&.reload&.status.in?(%w[done failed])
  end
end

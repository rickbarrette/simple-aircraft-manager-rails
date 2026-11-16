# Viewer mode (SAM_VIEWER=true, see Viewer): checks the database has no real
# accounts and imports SAM_VIEWER_ARCHIVE the first time. bin/docker-entrypoint
# runs it before the server starts.
namespace :sam do
  namespace :viewer do
    desc "Viewer mode: check the database and import the archive"
    task prepare: :environment do
      abort "SAM_VIEWER isn't on." unless Viewer.enabled?
      Viewer.prepare!
    rescue Viewer::RealAccounts, AircraftArchive::Error => e
      abort "Viewer: #{e.message}"
    end
  end
end

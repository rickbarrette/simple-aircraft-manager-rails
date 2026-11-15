# Uploaded files already answer Range requests (206), but don't say so. The
# PDF viewer on phones (PDF.js) needs "Accept-Ranges: bytes" to fetch only
# the parts of a PDF for the pages being looked at, instead of all of it.
Rails.application.config.to_prepare do
  ActiveStorage::DiskController.after_action(only: :show) do
    response.headers["Accept-Ranges"] = "bytes" if response.successful?
  end
end

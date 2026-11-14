# Uploads that claim to be images but can't be read as one (empty, corrupt,
# or another kind of file with an image name).
Rails.application.config.to_prepare do
  ActiveStorage::Blob.class_eval do
    # Worth resizing: an image kind that the upload check didn't find
    # unreadable. (Until that check has run, assume it's fine.)
    def resizable_image?
      variable? && !(metadata[:analyzed] && metadata[:width].blank?)
    end
  end

  # If resizing fails anyway, send the original rather than an error.
  ActiveStorage::Representations::BaseController.rescue_from(Vips::Error, ActiveStorage::InvariableError) do
    redirect_to Rails.application.routes.url_helpers.rails_blob_path(@blob, disposition: params[:disposition], only_path: true)
  end
end

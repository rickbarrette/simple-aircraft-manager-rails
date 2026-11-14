# Uploads that claim to be images but can't be read as one (empty, corrupt,
# or another kind of file with an image name): if resizing fails, send the
# original rather than an error.
Rails.application.config.to_prepare do
  ActiveStorage::Representations::BaseController.rescue_from(Vips::Error, ActiveStorage::InvariableError) do
    redirect_to Rails.application.routes.url_helpers.rails_blob_path(@blob, disposition: params[:disposition], only_path: true)
  end
end

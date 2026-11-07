# Direct uploads (the browser sends each file straight to storage, then submits
# only its signed id). Active Storage's own endpoint lets anyone create blobs;
# this one requires a signed-in user and applies the upload rules up front.
class DirectUploadsController < ActiveStorage::DirectUploadsController
  include Authentication
  before_action :check_upload, only: :create

  private

  def blob_args
    @blob_args ||= super.tap do |args|
      args[:content_type] = Marcel::MimeType.for(name: args[:filename].to_s) if args[:content_type].blank?
    end
  end

  def check_upload
    error =
      if !UploadValidation::ALLOWED_CONTENT_TYPES.include?(blob_args[:content_type])
        "#{blob_args[:filename]} isn't an allowed file type"
      elsif blob_args[:byte_size].to_i > UploadValidation::MAX_SIZE
        "#{blob_args[:filename]} is over #{UploadValidation::MAX_SIZE / 1.megabyte} MB"
      end
    render json: { error: error }, status: :unprocessable_entity if error
  end
end

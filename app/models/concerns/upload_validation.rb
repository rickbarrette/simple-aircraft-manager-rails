# Mirrors the original's ALLOWED_UPLOAD_EXTENSIONS / content-type checks.
module UploadValidation
  extend ActiveSupport::Concern

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp image/bmp image/tiff
    application/pdf text/plain application/gpx+xml application/xml text/xml
    text/csv application/vnd.google-earth.kml+xml application/octet-stream
  ].freeze
  MAX_SIZE = 50.megabytes

  class_methods do
    def validates_uploads(*names)
      validate do
        names.each do |name|
          Array(public_send(name).attachments).each do |att|
            next unless att.blob
            unless ALLOWED_CONTENT_TYPES.include?(att.blob.content_type)
              errors.add(name, "#{att.filename} is not an allowed file type")
            end
            errors.add(name, "#{att.filename} is too large") if att.blob.byte_size > MAX_SIZE
          end
        end
      end
    end
  end
end

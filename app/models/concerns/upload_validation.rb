# Mirrors the original's ALLOWED_UPLOAD_EXTENSIONS / content-type checks.
module UploadValidation
  extend ActiveSupport::Concern

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp image/bmp image/tiff
    application/pdf text/plain application/gpx+xml application/xml text/xml
    text/csv application/vnd.google-earth.kml+xml application/octet-stream
  ].freeze

  # Set by admins (Admin → Settings), default 50 MB.
  def self.max_size = Setting.max_upload_bytes

  class_methods do
    def validates_uploads(*names)
      validate do
        names.each do |name|
          Array(public_send(name).attachments).each do |att|
            next unless att.blob
            unless ALLOWED_CONTENT_TYPES.include?(att.blob.content_type)
              errors.add(name, :file_type, file: att.filename.to_s)
            end
            limit = UploadValidation.max_size
            errors.add(name, :file_size, file: att.filename.to_s, limit: limit / 1.megabyte) if att.blob.byte_size > limit
          end
        end
      end
    end
  end
end

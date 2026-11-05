# Keeps an uploaded spreadsheet in tmp/imports between the upload and confirm
# steps of an import. Tokens are server-generated "<uuid>.<ext>" and files are
# namespaced by aircraft, so a token can't be replayed elsewhere or used to
# reach other paths.
module StoredUpload
  extend ActiveSupport::Concern

  UPLOAD_DIR = Rails.root.join("tmp/imports")
  UPLOAD_MAX_SIZE = 10.megabytes
  UPLOAD_EXTENSIONS = %w[xlsx csv].freeze
  TOKEN_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\.(xlsx|csv)\z/

  private

  # Returns [token, nil] on success or [nil, error message].
  def store_upload(file)
    return [ nil, "Choose a file to upload." ] unless file.respond_to?(:path)
    return [ nil, "File is too large." ] if file.size > UPLOAD_MAX_SIZE
    ext = File.extname(file.original_filename.to_s).delete(".").downcase
    return [ nil, "Upload an .xlsx or .csv file." ] unless ext.in?(UPLOAD_EXTENSIONS)

    FileUtils.mkdir_p(UPLOAD_DIR)
    Dir.glob(UPLOAD_DIR.join("*")).each { |f| File.delete(f) if File.mtime(f) < 1.day.ago }
    token = "#{SecureRandom.uuid}.#{ext}"
    FileUtils.cp(file.path, stored_path(token))
    [ token, nil ]
  end

  def stored_file?(token)
    TOKEN_FORMAT.match?(token.to_s) && File.exist?(stored_path(token))
  end

  def stored_path(token)
    UPLOAD_DIR.join("#{@aircraft.id}-#{File.basename(token.to_s)}")
  end

  def discard_upload(token)
    File.delete(stored_path(token)) if stored_file?(token)
  end
end

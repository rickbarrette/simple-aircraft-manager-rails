namespace :offsite do
  desc "Restore uploaded files missing from storage, from Google Drive or from a downloaded copy of its files folder: offsite:restore_files[DIR]"
  task :restore_files, [ :dir ] => :environment do |_, args|
    dir = args[:dir].presence
    connection = OffsiteConnection.current
    abort "Google Drive isn't connected: download the backup's files folder and pass its path, e.g. offsite:restore_files[/path/to/files]" if dir.nil? && !connection.connected?
    if dir.nil?
      drive = connection.client
      drive_ids = drive.list(connection.files_folder_id).to_h { [ _1["name"], _1["id"] ] }
    end
    restored = 0
    missing = []
    ActiveStorage::Blob.find_each do |blob|
      next if blob.service.exist?(blob.key)
      io = if dir
        path = File.join(dir, blob.key)
        File.open(path, "rb") if File.file?(path)
      elsif (id = drive_ids[blob.key])
        drive.download(id, to: Tempfile.new("sam-restore", binmode: true))
      end
      next missing << "#{blob.key} (#{blob.filename})" unless io
      begin
        blob.service.upload(blob.key, io, checksum: blob.checksum)
        restored += 1
      ensure
        io.close
      end
    end
    puts "Restored #{restored} #{'file'.pluralize(restored)}."
    puts "Not found (#{missing.size}):", missing.first(50) if missing.any?
  end
end

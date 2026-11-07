require "active_storage/service/disk_service"

module ActiveStorage
  # Disk storage that keeps one copy of each distinct file. A stored file's
  # bytes live once under .objects/ab/cd/<sha256>, and every blob (and variant)
  # with those bytes is a hard link to it, so uploading the same scan twice
  # costs no extra space. Blobs, filenames and URLs are unchanged.
  #
  # Linked files must never be written in place, so an upload over an existing
  # key first unlinks it. If the filesystem can't hard-link (some network
  # shares), files are simply kept as plain copies.
  #
  # #sweep links in files stored before this service (or that failed to link)
  # and removes objects no blob uses any more; it runs nightly.
  class Service::DedupDiskService < Service::DiskService
    OBJECTS_DIR = ".objects".freeze

    def upload(key, io, checksum: nil, **)
      release(path_for(key))
      super
      adopt(path_for(key))
    end

    def compose(source_keys, destination_key, **)
      release(path_for(destination_key))
      super
      adopt(path_for(destination_key))
    end

    def delete(key)
      instrument :delete, key: key do
        release(path_for(key))
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        prefix_path = path_for(prefix)
        prefix_path += "/" if prefix.end_with?("/")
        Dir.glob("#{escape_glob_metacharacters(prefix_path)}*").each do |path|
          files = File.directory?(path) ? Dir.glob("#{escape_glob_metacharacters(path)}/**/*") : [ path ]
          files.each { release(_1) if File.file?(_1) }
          FileUtils.rm_rf(path)
        end
      end
    end

    # Returns { linked:, removed:, saved_bytes: }.
    def sweep
      linked = Dir.glob(File.join(escape_glob_metacharacters(root), "??", "??", "**", "*")).count do |path|
        File.file?(path) && !File.symlink?(path) && adopt(path) == :shared
      end
      removed = 0
      saved = 0
      Dir.glob(File.join(escape_glob_metacharacters(objects_root), "**", "*")).each do |object|
        next unless File.file?(object)
        stat = File.stat(object)
        if stat.nlink == 1
          File.delete(object)
          removed += 1
        else
          saved += stat.size * (stat.nlink - 2)
        end
      end
      { linked: linked, removed: removed, saved_bytes: saved }
    end

    private

    def objects_root = File.join(root, OBJECTS_DIR)

    def object_path(digest) = File.join(objects_root, digest[0..1], digest[2..3], digest)

    # Points a freshly written file at the stored copy of its bytes (or makes it
    # the stored copy). Returns :stored, :shared, or nil if left alone.
    def adopt(path)
      return unless File.stat(path).nlink == 1
      object = object_path(Digest::SHA256.file(path).hexdigest)
      FileUtils.mkdir_p(File.dirname(object))
      begin
        File.link(path, object)
        :stored
      rescue Errno::EEXIST
        return unless File.size(object) == File.size(path)
        temp = "#{path}.#{SecureRandom.hex(6)}.link"
        File.link(object, temp)
        File.rename(temp, path) # atomic swap: readers see one file or the other
        :shared
      end
    rescue SystemCallError => e
      Rails.logger.warn("[dedup storage] kept a plain copy of #{path}: #{e.class}: #{e.message}")
      nil
    end

    # Unlinks a blob's file, and its stored object if nothing else uses it.
    def release(path)
      stat = File.stat(path)
      if stat.nlink == 2
        object = object_path(Digest::SHA256.file(path).hexdigest)
        File.delete(object) if File.exist?(object) && File.stat(object).ino == stat.ino
      end
      File.delete(path)
    rescue Errno::ENOENT
      # already gone
    end
  end
end

require "test_helper"
require "active_storage/service/dedup_disk_service"

class DedupDiskServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @root = Dir.mktmpdir
    @service = ActiveStorage::Service::DedupDiskService.new(root: @root)
  end

  teardown { FileUtils.rm_rf(@root) }

  def put(key, body) = @service.upload(key, StringIO.new(body), checksum: OpenSSL::Digest::MD5.base64digest(body))
  def path(key) = @service.path_for(key)
  def objects = Dir.glob(File.join(@root, ".objects/**/*")).select { File.file?(_1) }

  test "identical files share one stored copy; different files don't" do
    put "aaaa1111", "same scan"
    put "bbbb2222", "same scan"
    put "cccc3333", "other scan"
    assert_equal File.stat(path("aaaa1111")).ino, File.stat(path("bbbb2222")).ino
    refute_equal File.stat(path("aaaa1111")).ino, File.stat(path("cccc3333")).ino
    assert_equal 2, objects.size
    assert_equal "same scan", @service.download("bbbb2222")
  end

  test "deleting one copy keeps the other; deleting the last frees the object" do
    put "aaaa1111", "same scan"
    put "bbbb2222", "same scan"
    @service.delete("aaaa1111")
    assert_equal "same scan", @service.download("bbbb2222")
    assert_equal 1, objects.size
    @service.delete("bbbb2222")
    assert_empty objects
    refute @service.exist?("bbbb2222")
  end

  test "re-uploading a shared key never changes the other blob" do
    put "aaaa1111", "same scan"
    put "bbbb2222", "same scan"
    put "aaaa1111", "replaced"
    assert_equal "replaced", @service.download("aaaa1111")
    assert_equal "same scan", @service.download("bbbb2222")
  end

  test "a checksum mismatch stores nothing" do
    assert_raises(ActiveStorage::IntegrityError) { @service.upload("aaaa1111", StringIO.new("bytes"), checksum: "bm9wZQ==") }
    refute @service.exist?("aaaa1111")
    assert_empty objects
  end

  test "variants under a prefix are released too" do
    put "variants/aaaa1111/thumb", "same scan"
    put "bbbb2222", "same scan"
    @service.delete_prefixed("variants/aaaa1111/")
    refute @service.exist?("variants/aaaa1111/thumb")
    assert_equal "same scan", @service.download("bbbb2222")
    assert_equal 1, objects.size
  end

  test "sweep links files stored before dedup and clears unused objects" do
    plain = ActiveStorage::Service::DiskService.new(root: @root)
    plain.upload("aaaa1111", StringIO.new("old scan"))
    plain.upload("bbbb2222", StringIO.new("old scan"))
    put "cccc3333", "gone soon"
    File.delete(path("cccc3333")) # e.g. a crash between unlinks

    assert_equal({ linked: 1, removed: 1, saved_bytes: 8 }, @service.sweep)
    assert_equal File.stat(path("aaaa1111")).ino, File.stat(path("bbbb2222")).ino
    assert_equal({ linked: 0, removed: 0, saved_bytes: 8 }, @service.sweep)
  end

  test "attachments through Active Storage share storage but keep their own filenames" do
    a = create_aircraft
    one = a.documents.create!(name: "Receipt", doc_type: "OTHER", pages: [ { io: StringIO.new("%PDF same"), filename: "receipt.pdf", content_type: "application/pdf" } ])
    two = a.documents.create!(name: "Invoice", doc_type: "OTHER", pages: [ { io: StringIO.new("%PDF same"), filename: "invoice.pdf", content_type: "application/pdf" } ])
    service = ActiveStorage::Blob.service
    assert_kind_of ActiveStorage::Service::DedupDiskService, service
    keys = [ one, two ].map { _1.pages.first.blob.key }
    assert_equal File.stat(service.path_for(keys[0])).ino, File.stat(service.path_for(keys[1])).ino
    assert_equal %w[receipt.pdf invoice.pdf], [ one, two ].map { _1.pages.first.filename.to_s }
    perform_enqueued_jobs { one.destroy! }
    assert_equal 1, ActiveStorage::Blob.count
    assert_equal "%PDF same", two.pages.first.download
  end
end

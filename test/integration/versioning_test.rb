require "test_helper"

# Releases: version (YYYY.MM.N, from VERSION) plus build (the commit), and
# release notes (CHANGELOG.md) as "What's new".
class VersioningTest < ActionDispatch::IntegrationTest
  test "the version comes from VERSION; About shows version, build and What's new" do
    version = File.read(Rails.root.join("VERSION")).strip
    assert_match(/\A\d{4}\.\d{1,2}\.\d+\z/, version)
    info = SystemInfo.new
    assert_equal version, info.version
    assert_equal "#{version} (build #{info.revision})", info.version_label

    sign_in create_user("admin@example.com", admin: true)
    get admin_about_path
    assert_select "[data-version]", text: version
    assert_select "[data-revision]", text: /Build/
    assert_select "a[href='#{help_page_path('changelog')}']", text: "What's new"

    get help_page_path("changelog")
    assert_response :success
    assert_select "h1", text: /What.s new/
    assert_select "h2", text: version # the current version has release notes
  end

  test "each recorded software build remembers its version" do
    AppRevision.touch_current!
    revision = AppRevision.find_by(revision: SystemInfo.new.revision)
    skip "no git revision in this environment" unless revision
    assert_equal SystemInfo.new.version, revision.version
  end
end

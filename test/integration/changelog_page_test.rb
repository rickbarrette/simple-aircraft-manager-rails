require "test_helper"

# What's new: the running version's notes on About, and the history with
# older releases folded to one line each, by month.
class ChangelogPageTest < ActionDispatch::IntegrationTest
  test "the history opens this version and folds older releases, grouped by month" do
    log = Changelog.load
    version = SystemInfo.new.version
    sign_in create_user
    get help_page_path("changelog")
    assert_response :success
    assert_select "details.release", log.releases.size
    assert_select "details.release[open]##{log.release(version).anchor}" do
      assert_select "summary .badge-blue", text: "This version"
    end
    older = log.releases.drop(log.releases.index { _1.version == version } + 1)
    older.each { |r| assert_select "details.release:not([open])##{r.anchor} summary", text: /#{Regexp.escape(r.version)}.*(change|fix|for administrators|note)/m }
    assert_select "h2", text: "November 2026"
  end

  test "About shows what's new in the running version, linking to all releases" do
    version = SystemInfo.new.version
    sign_in create_user("admin@example.com", admin: true)
    get admin_about_path
    assert_select "#whats-new" do
      assert_select "h2", text: "What's new in #{version}"
      assert_select "a[href='#{help_page_path('changelog')}']", text: "All releases"
      assert_select "h3", minimum: 1 # its sections (Changes, Fixes, ...)
    end
  end
end

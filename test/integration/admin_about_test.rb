require "test_helper"

class AdminAboutTest < ActionDispatch::IntegrationTest
  test "admins see versions and setup; nobody else can" do
    sign_in create_user("pilot@example.com")
    get admin_about_path
    assert_redirected_to root_path

    admin = create_user("admin@example.com", admin: true)
    sign_in admin
    get root_path
    assert_select "a[href='#{admin_about_path}']", text: "About"

    with_env("APP_REVISION" => "abc1234", "APP_BUILT_AT" => "2026-11-07T12:00:00Z", "ANTHROPIC_API_KEY" => "sk-ant-secret") do
      get admin_about_path
    end
    assert_response :success
    assert_select "[data-revision] a[href='#{SystemInfo::REPOSITORY_URL}/commit/abc1234']", text: "abc1234"
    assert_select "a[href='#{SystemInfo::REPOSITORY_URL}']", text: "Source code"
    body = response.body
    [ RUBY_VERSION, Rails.version, SQLite3::SQLITE_VERSION, Gem.loaded_specs["turbo-rails"].version.to_s ].each { assert_includes body, _1 }
    assert_includes body, "on (#{LogbookTranscriber::MODEL})"
    refute_includes body, "sk-ant-secret" # configured or not; never the value
    assert_select "summary", text: /All gems \(\d+\)/
  end

  test "storage figures count files stored once" do
    info = SystemInfo.new
    2.times { |i| ActiveStorage::Blob.create_and_upload!(io: StringIO.new("same bytes"), filename: "copy#{i}.txt") }
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("other"), filename: "other.txt")
    assert_equal({ files: 3, bytes: 25, shared_bytes: 10 }, info.storage.slice(:files, :bytes, :shared_bytes))
  end

  private

  def with_env(vars)
    saved = vars.keys.to_h { [ _1, ENV[_1] ] }
    vars.each { ENV[_1] = _2 }
    yield
  ensure
    saved.each { ENV[_1] = _2 }
  end
end

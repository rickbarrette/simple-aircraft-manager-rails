require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "manifest is public and points at icons that exist" do
    get pwa_manifest_path(format: :json)
    assert_response :success
    manifest = JSON.parse(response.body)
    assert_equal "Simple Aircraft Manager", manifest["name"]
    assert_equal "standalone", manifest["display"]
    assert_includes manifest["icons"].map { _1["purpose"] }, "maskable"
    manifest["icons"].each { |icon| assert Rails.public_path.join(icon["src"].delete_prefix("/")).exist?, icon["src"] }
    assert_equal "en", manifest["lang"]
    assert_equal %w[/go/log-flight /go/report-squawk], manifest["shortcuts"].map { _1["url"] }
  end

  test "service worker is public and precaches files that exist" do
    get pwa_service_worker_path(format: :js)
    assert_response :success
    assert_match "javascript", response.media_type
    shell = response.body[/const SHELL = \[(.*?)\]/, 1].scan(/"([^"]+)"/).flatten
    assert_includes shell, "/offline"
    shell.each do |path|
      next assert(Rails.public_path.join(path.delete_prefix("/")).exist?, path) if path.include?(".")
      get path
      assert_response :success, path # rendered pages (the offline page) work signed out
    end
    get pwa_service_worker_path(format: :js)
    assert_match(/const VERSION = "#{SystemInfo.new.revision}-en"/, response.body) # a new build refreshes the cached shell
  end

  test "signed-in and shared pages link the manifest and register the worker" do
    sign_in create_user
    get root_path
    assert_select "link[rel=manifest][href='/manifest.json'][crossorigin=use-credentials]" # behind an auth proxy (Authentik) the manifest needs cookies
    assert_select "meta[name=theme-color]"
    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png']"
    assert_select "link[rel=icon][href='/favicon.svg']"
    assert_includes Rails.public_path.join("favicon.svg").read, "✈️"

    token = create_aircraft(owner: create_user("o2@example.com")).share_tokens.create!(privilege: "status")
    get shared_path(token.token)
    assert_select "link[rel=manifest]"
  end
end

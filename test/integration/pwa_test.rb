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
  end

  test "service worker is public and precaches files that exist" do
    get pwa_service_worker_path(format: :js)
    assert_response :success
    assert_match "javascript", response.media_type
    shell = response.body[/const SHELL = \[(.*?)\]/, 1].scan(/"([^"]+)"/).flatten
    assert_includes shell, "/offline.html"
    shell.each { |path| assert Rails.public_path.join(path.delete_prefix("/")).exist?, path }
  end

  test "signed-in and shared pages link the manifest and register the worker" do
    sign_in create_user
    get root_path
    assert_select "link[rel=manifest][href='/manifest.json']"
    assert_select "meta[name=theme-color]"
    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png']"

    token = create_aircraft(owner: create_user("o2@example.com")).share_tokens.create!(privilege: "status")
    get shared_path(token.token)
    assert_select "link[rel=manifest]"
  end
end

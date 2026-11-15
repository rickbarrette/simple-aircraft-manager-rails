require "test_helper"

# The top bar turns red when the server can't be reached and has a ring for
# saving for offline / sending (connection_controller.js); here, its markup,
# styles and strings.
class ConnectionStatusTest < ActionDispatch::IntegrationTest
  test "the top bar carries the connection status, hidden ring and announcer" do
    sign_in create_user
    get root_path
    assert_select "header[data-controller=connection]" do
      assert_select ".sync-ring[hidden][role=img][data-connection-target=ring] [data-connection-target=label]"
      assert_select "[role=status][data-connection-target=announce]"
    end
    strings = JSON.parse(css_select("script#i18n").first.text)
    assert_equal %w[back_online offline saving sending waiting], strings["connection"].keys.sort
    assert_match "%{percent}", strings["connection"]["saving"]
  end

  test "signed out pages have it too, for the sign-in page offline" do
    create_user
    get new_session_path
    assert_response :success
    assert_select "header[data-controller=connection] .sync-ring[hidden]"
  end

  test "the red top bar and the ring are styled" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    assert_match(/header\.is-offline \{ --color-header: var\(--color-header-offline\); \}/, css)
    assert_match "conic-gradient", css
  end
end

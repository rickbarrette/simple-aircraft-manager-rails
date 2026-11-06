require "test_helper"

class ThemeTest < ActionDispatch::IntegrationTest
  test "pages set the theme before paint and offer a toggle" do
    sign_in create_user
    get root_path
    head = response.body[/<head>.*?<\/head>/m]
    assert_match "localStorage.getItem(\"theme\")", head
    assert head.index("dataset.theme") < head.index("stylesheet"), "theme script must run before the stylesheet loads"
    assert_select "header button[data-controller='theme']"
    assert_select "html.bg-page"
  end

  test "shared (public) pages support dark mode too" do
    owner = create_user
    token = create_aircraft(owner: owner).share_tokens.create!(privilege: "status")
    get shared_path(token.token)
    assert_select "header button[data-controller='theme']"
    assert_match "dataset.theme", response.body
  end

  test "stylesheet has the dark palette" do
    css = Rails.root.join("app/assets/builds/tailwind.css").read
    assert_match ":root[data-theme=dark]", css
    assert_match "color-scheme:dark", css
  end
end

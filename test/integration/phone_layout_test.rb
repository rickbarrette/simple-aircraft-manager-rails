require "test_helper"

class PhoneLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user("owner@example.com", admin: true)
    @a = create_aircraft(owner: @user)
    sign_in @user
  end

  test "phones get a compact header with one menu, and a section menu instead of the tab strip" do
    get aircraft_components_path(@a)
    assert_select "header nav.sm\\:hidden summary[aria-label=Menu]"
    assert_select "header nav.sm\\:hidden form[action='#{session_path}']" # sign out lives in the menu
    assert_select "header nav.sm\\:hidden a[href='#{admin_users_path}']"
    assert_select "details.md\\:hidden summary", text: /Section\s*Components/
    assert_select "details.md\\:hidden nav a[aria-current=page]", "Components"
    assert_select "details.md\\:hidden nav a", count: 15
    assert_select "nav.md\\:flex a.tab-active", "Components" # wider screens keep the tabs
  end

  test "wide grids opt out of the stacked phone table" do
    @a.oil_analyses.create!(sample_date: Date.current, elements: { iron: 30 })
    get aircraft_oil_analyses_path(@a)
    assert_select "table.table.table-keep", 1
  end
end

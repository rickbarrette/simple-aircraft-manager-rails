require "test_helper"

# Each section shows its main action; imports, exports, printing and the
# aircraft's own settings are under a "More" menu.
class MoreMenuTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot)
  end

  test "secondary actions are in the More menu and the main action stays a button" do
    sign_in @owner
    get aircraft_flight_logs_path(@a)
    assert_select "details summary", /More/
    assert_select ".menu a.menu-item[href='#{new_aircraft_flight_import_path(@a)}']", "Import from spreadsheet"
    assert_select ".menu a.menu-item[href='#{new_aircraft_air_trail_export_path(@a)}']", "Export for AirTrail"

    get aircraft_logbook_entries_path(@a)
    assert_select "a.btn-primary[href='#{new_aircraft_logbook_entry_path(@a)}']", "+ New Entry"
    assert_select ".menu a.menu-item[href='#{new_aircraft_logbook_import_path(@a)}']", "Import scans"
  end

  test "the aircraft's More menu has access and downloads for owners only" do
    sign_in @owner
    get aircraft_path(@a)
    assert_select "nav[aria-label='Aircraft sections'] a", text: "Access & Sharing", count: 0
    assert_select ".menu a.menu-item[href='#{aircraft_aircraft_roles_path(@a)}']", "Access & sharing"
    assert_select ".menu a.menu-item[href='#{aircraft_export_path(@a)}']", "Download .sam.zip"

    sign_in @pilot
    get aircraft_path(@a)
    assert_select ".menu a.menu-item[href='#{aircraft_report_path(@a)}']", "Status report"
    assert_select ".menu a[href='#{aircraft_aircraft_roles_path(@a)}']", count: 0
    assert_select ".menu a[href='#{aircraft_export_path(@a)}']", count: 0
  end

  test "the header shows the role on the aircraft, and Available only when it isn't the usual" do
    admin = create_user("admin@example.com", admin: true)
    @a.roles.create!(user: admin, role: "owner")
    sign_in admin
    get aircraft_path(@a)
    assert_select "span[title='Your access to this aircraft']", "Owner"
    assert_select "span.badge-green", text: "Available", count: 0
  end

  test "the description keeps its paragraphs inside the Details card" do
    @a.update!(description: "First line.\n\nSecond paragraph.")
    sign_in @owner
    get aircraft_path(@a)
    # simple_format makes <p>s, so the box around them must not be a <p> (they'd spill out of it).
    assert_select "div.border-t > p", 2
  end
end

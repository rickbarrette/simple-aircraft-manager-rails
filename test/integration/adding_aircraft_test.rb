require "test_helper"

# Who can add aircraft (Admin → Settings): adding or importing one makes you
# its Owner, who can bring in outside mechanics, so by default only
# administrators can.
class AddingAircraftTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user("user@example.com")
    @admin = create_user("admin@example.com", admin: true)
  end

  test "by default only administrators add or import aircraft" do
    sign_in @user
    get root_path
    assert_select "a[href=?]", new_aircraft_path, 0
    assert_select "a[href=?]", new_aircraft_import_path, 0
    assert_includes response.body, "An administrator adds aircraft"
    get new_aircraft_path
    assert_redirected_to root_path
    post aircraft_index_path, params: { aircraft: { tail_number: "N1", tach_time: 50 } }
    assert_not Aircraft.exists?(tail_number: "N1")
    get new_aircraft_import_path
    assert_redirected_to root_path

    sign_in @admin
    post aircraft_index_path, params: { aircraft: { tail_number: "N1", tach_time: 50 } }
    assert_equal "owner", @admin.role_for(Aircraft.find_by!(tail_number: "N1")).key
  end

  test "an administrator can let everyone add aircraft" do
    sign_in @admin
    get edit_admin_settings_path
    assert_select "select[name='settings[anyone_adds_aircraft]'] option[selected]", text: "Administrators only"
    patch admin_settings_path, params: { settings: { anyone_adds_aircraft: 1 } }
    assert Setting.anyone_adds_aircraft?

    sign_in @user
    get root_path
    assert_select "a[href=?]", new_aircraft_path
    post aircraft_index_path, params: { aircraft: { tail_number: "N2", tach_time: 50 } }
    assert_equal "owner", @user.role_for(Aircraft.find_by!(tail_number: "N2")).key
  end
end

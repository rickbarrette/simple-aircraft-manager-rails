require "test_helper"

class SetupTest < ActionDispatch::IntegrationTest
  test "first run creates admin, then setup is closed" do
    get root_path
    assert_redirected_to new_setup_path
    post setup_path, params: { user: { name: "Jane", email_address: "a@b.com", password: "test-password-123", password_confirmation: "test-password-123" } }
    assert_redirected_to root_path
    assert User.last.admin?
    get new_setup_path
    assert_redirected_to root_path
  end

  test "create aircraft makes creator the owner" do
    user = create_user
    sign_in user
    post aircraft_index_path, params: { aircraft: { tail_number: "N1", tach_time: 50 } }
    a = Aircraft.find_by!(tail_number: "N1")
    assert_redirected_to aircraft_path(a)
    assert_equal "owner", user.role_for(a)
  end
end

require "test_helper"

# Configurable roles (Role, Permission): what each built-in role can do, a
# custom role, who can hand out roles, administrators managing them, and
# that every action that changes something declares the permission it needs.
class RolesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @admin = create_user("admin@example.com", admin: true)
    @a = create_aircraft(owner: @owner, tail_number: "N12345", tach_time: 1000)
  end

  def member(email, role)
    create_user(email).tap { @a.roles.create!(user: _1, role: role) }
  end

  test "every action that changes something declares the permission it needs" do
    missing = Rails.application.routes.routes.filter_map do |route|
      verb, controller, action = route.verb, route.defaults[:controller], route.defaults[:action]
      next if controller.blank? || verb.blank? || verb.match?(/\A(GET|HEAD)?\z/)
      klass = "#{controller.camelize}Controller".safe_constantize
      next unless klass && klass < ApplicationController && klass.include?(AircraftScoped)
      next if klass._process_action_callbacks.none? { _1.filter == :authorize_permission! && _1.kind == :before } ||
              (klass == AircraftController && action == "create") # adding an aircraft makes you its Owner
      rules = klass.permission_rules.select { |_, only, except| (only.nil? || only.include?(action)) && (except.nil? || except.exclude?(action)) }
      "#{verb} #{controller}##{action}" if rules.empty?
    end
    assert_empty missing.uniq, "actions without a permission"
  end

  test "the built-in roles: Owner has everything, the others their defaults, and none can be deleted" do
    Role.ensure_built_in!
    assert_equal Permission::ALL, Role.owner.permissions
    assert_equal Permission::DEFAULTS["pilot"].sort, Role.for_key("pilot").permissions.sort
    assert_empty Role.for_key("viewer").permissions
    assert_not Role.for_key("pilot").destroy
    Role.owner.update!(permissions: [])
    assert_equal Permission::ALL, Role.owner.reload.permissions
  end

  test "a viewer sees the records and can change nothing" do
    viewer = member("viewer@example.com", "viewer")
    sign_in viewer
    get aircraft_path(@a)
    assert_response :success
    assert_select "a[href=?]", new_aircraft_flight_log_path(@a), 0
    assert_select "a[href=?]", new_aircraft_squawk_path(@a), 0
    assert_select "form[action=?]", hours_aircraft_path(@a), 0
    assert_select ".badge-gray", text: "Viewer"

    post aircraft_flight_logs_path(@a), params: { flight_log: { date: Date.current, tach_out: 1000, tach_in: 1001 } }
    assert_redirected_to aircraft_path(@a)
    assert_equal "Your role on this aircraft doesn't allow that.", flash[:alert]
    post aircraft_squawks_path(@a), params: { squawk: { priority: 1, issue_reported: "x" } }
    patch hours_aircraft_path(@a), params: { tach_time: 1010 }
    post aircraft_notes_path(@a), params: { aircraft_note: { text: "hi" } }
    assert_equal 0, @a.flight_logs.count
    assert_equal 0, @a.squawks.count
    assert_equal 0, @a.notes.count
    assert_equal 1000, @a.reload.tach_time
  end

  test "a mechanic maintains the aircraft but doesn't fly it or manage its people" do
    mechanic = member("mech@example.com", "mechanic")
    squawk = @a.squawks.create!(priority: 1, issue_reported: "Loose cowl")
    sign_in mechanic
    post aircraft_components_path(@a), params: { component: { component_type_id: component_type.id, manufacturer: "Lycoming", model: "O-320", date_in_service: Date.current } }
    assert_equal 1, @a.components.count
    patch aircraft_squawk_path(@a, squawk), params: { squawk: { issue_reported: "Loose cowl fastener" } }
    assert_equal "Loose cowl fastener", squawk.reload.issue_reported

    post aircraft_flight_logs_path(@a), params: { flight_log: { date: Date.current, tach_out: 1000, tach_in: 1001 } }
    assert_equal 0, @a.flight_logs.count
    post aircraft_aircraft_roles_path(@a), params: { email_address: "owner@example.com", role_id: Role.for_key("viewer").id }
    assert_equal "owner", @a.roles.find_by(user: @owner).role.key
    get aircraft_aircraft_roles_path(@a)
    assert_redirected_to aircraft_path(@a)
  end

  test "a custom role gets exactly what's ticked, and managing people doesn't make you an Owner" do
    role = Role.create!(name: "Partner", permissions: %w[log_flights manage_people])
    partner = member("partner@example.com", role)
    sign_in partner
    post aircraft_flight_logs_path(@a), params: { flight_log: { date: Date.current, tach_out: 1000, tach_in: 1001 } }
    assert_equal 1, @a.flight_logs.count
    post aircraft_squawks_path(@a), params: { squawk: { priority: 1, issue_reported: "x" } }
    assert_equal 0, @a.squawks.count

    get aircraft_aircraft_roles_path(@a)
    assert_response :success
    assert_select "select[name=role_id] option", text: "Owner", count: 0
    newbie = create_user("newbie@example.com")
    post aircraft_aircraft_roles_path(@a), params: { email_address: newbie.email_address, role_id: Role.owner.id }
    assert_nil @a.roles.find_by(user: newbie)
    post aircraft_aircraft_roles_path(@a), params: { email_address: newbie.email_address, role_id: Role.for_key("viewer").id }
    assert_equal "viewer", @a.roles.find_by(user: newbie).role.key

    mine = @a.roles.find_by(user: partner)
    patch aircraft_aircraft_role_path(@a, mine), params: { role_id: Role.owner.id }
    assert_equal role, mine.reload.role
    owners = @a.roles.find_by(user: @owner)
    patch aircraft_aircraft_role_path(@a, owners), params: { role_id: Role.for_key("viewer").id }
    delete aircraft_aircraft_role_path(@a, owners)
    assert_equal "owner", owners.reload.role.key
  end

  test "administrators manage roles: create, change, and delete only unused custom ones" do
    sign_in @admin
    get admin_roles_path
    assert_select "tr.role-row", 4
    post admin_roles_path, params: { role: { name: "Instructor", description: "Teaches in it", permissions: [ "", "log_flights", "bogus" ] } }
    role = Role.find_by!(name: "Instructor")
    assert_equal %w[log_flights], role.permissions

    patch admin_role_path(role), params: { role: { name: "Instructor", permissions: [ "" ] } }
    assert_empty role.reload.permissions
    patch admin_role_path(Role.owner), params: { role: { name: "Owner", permissions: [ "" ] } }
    assert_equal Permission::ALL, Role.owner.reload.permissions

    @a.roles.create!(user: create_user, role: role)
    delete admin_role_path(role)
    assert Role.exists?(role.id)
    delete admin_role_path(Role.for_key("viewer"))
    assert Role.for_key("viewer")
    @a.roles.where(role: role).destroy_all
    delete admin_role_path(role)
    assert_not Role.exists?(role.id)
  end

  test "administrators give people roles on any aircraft, keeping an Owner" do
    person = create_user("person@example.com")
    sign_in @admin
    get edit_admin_user_path(person)
    assert_select "#access select[name=aircraft_id] option", text: "N12345"
    post admin_user_aircraft_roles_path(person), params: { aircraft_id: @a.id, role_id: Role.for_key("mechanic").id }
    membership = @a.roles.find_by!(user: person)
    assert_equal "mechanic", membership.role.key

    patch admin_user_aircraft_role_path(person, membership), params: { role_id: Role.owner.id }
    assert_equal "owner", membership.reload.role.key
    owner_membership = @a.roles.find_by(user: @owner)
    delete admin_user_aircraft_role_path(@owner, owner_membership)
    assert_not AircraftRole.exists?(owner_membership.id)
    delete admin_user_aircraft_role_path(person, membership)
    assert AircraftRole.exists?(membership.id), "the last Owner stays"

    sign_in create_user("nobody@example.com")
    post admin_user_aircraft_roles_path(person), params: { aircraft_id: @a.id, role_id: Role.owner.id }
    assert_equal 1, @a.roles.count
  end

  test "reminders go to roles that get them" do
    mechanic = member("mech@example.com", "mechanic")
    pilot = member("pilot@example.com", "pilot")
    @a.squawks.create!(priority: 0, issue_reported: "Grounding")
    assert_equal [ @a ], ReminderMailer.items_for(@owner).map(&:first)
    assert_equal [ @a ], ReminderMailer.items_for(mechanic).map(&:first)
    assert_empty ReminderMailer.items_for(pilot)
  end

  test "the API follows the person's role" do
    viewer = member("viewer@example.com", "viewer")
    token = ApiToken.create!(name: "script", kind: "personal", user: viewer, scopes: %w[read squawks:write])
    post "/api/v1/aircraft/#{@a.id}/squawks", params: { squawk: { issue_reported: "x", priority: 1 } },
         headers: { "Authorization" => "Bearer #{token.token}" }, as: :json
    assert_response :forbidden
    assert_equal "not_permitted", JSON.parse(response.body).dig("error", "code")
  end
end

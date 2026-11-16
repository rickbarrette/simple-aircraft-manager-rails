require "test_helper"

# Invitation codes (AccessInvitation): a link that gives an account and roles
# on aircraft, made by administrators or by whoever manages an aircraft's
# people, used by new people (creating an account) or existing ones.
class InvitationsTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-unique-test-passphrase-42".freeze

  setup do
    @owner = create_user("owner@example.com")
    @admin = create_user("admin@example.com", admin: true)
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    @b = create_aircraft(owner: @owner, tail_number: "N54321")
  end

  def invitation(creator: @admin, grants: [ [ @a, "mechanic" ] ], **attrs)
    AccessInvitation.create_for(creator, { label: "Test", max_uses: 1 }.merge(attrs), grants.map { |a, key| [ a, Role.for_key(key) ] })
  end

  def join_link_in(body) = body[%r{/join/[\w-]+}]

  test "an administrator invites to several aircraft; the link is shown once and the code kept only as a digest" do
    sign_in @admin
    get new_admin_invitation_path
    assert_select "select[name='roles[#{@a.id}]']"
    post admin_invitations_path, params: { access_invitation: { label: "Club pilots", max_uses: 5, expires_at: "" },
                                           roles: { @a.id => Role.for_key("pilot").id, @b.id => Role.for_key("viewer").id } }
    assert_response :success
    link = join_link_in(response.body)
    assert link
    inv = AccessInvitation.last
    assert_equal({ "N12345" => "Pilot", "N54321" => "Viewer" }, inv.grants.to_h { [ _1.aircraft.tail_number, _1.role.name ] })
    assert_nil inv.expires_at
    assert_not_includes inv.attributes.values.map(&:to_s), link.split("/").last
    get admin_invitations_path
    assert_select "tr.invitation-row", 1
    assert_not_includes response.body, link
  end

  test "someone new opens the link, creates an account and gets the roles; a single-use link then stops working" do
    inv = invitation(grants: [ [ @a, "mechanic" ], [ @b, "viewer" ] ])
    get join_path(inv.token)
    assert_response :success
    assert_select ".badge-blue", text: "Mechanic"
    post account_join_path(inv.token), params: { email_address: "New@Example.com", name: "New Mechanic", password: PASSWORD, password_confirmation: PASSWORD }
    assert_redirected_to root_path
    assert_match "Welcome! Your account is ready. N12345: Mechanic N54321: Viewer", flash[:notice]
    user = User.find_by!(email_address: "new@example.com")
    assert_equal "mechanic", user.role_for(@a).key
    assert_equal 1, inv.reload.uses_count
    assert inv.redeemed_by?(user)

    delete session_path
    get join_path(inv.token)
    assert_response :not_found
    assert_select "h1", text: "This invitation isn't valid"
  end

  test "someone with an account signs in and accepts; a role they already have stays" do
    pilot = create_user("pilot@example.com")
    @b.roles.create!(user: pilot, role: "owner")
    inv = invitation(grants: [ [ @a, "pilot" ], [ @b, "viewer" ] ], max_uses: nil)
    get join_path(inv.token)
    assert_select "a[href=?]", new_session_path
    sign_in pilot # returns to the invitation
    assert_equal join_path(inv.token), path
    assert_select "form[action=?]", accept_join_path(inv.token)
    post accept_join_path(inv.token)
    assert_match "N12345: Pilot N54321: already Owner, unchanged", flash[:notice]
    assert_equal "owner", pilot.role_for(@b).key
    assert_equal "pilot", pilot.role_for(@a).key
    post accept_join_path(inv.token)
    assert_equal "You've already accepted this invitation.", flash[:notice]
    assert_equal 1, inv.reload.uses_count
  end

  test "an invitation for one address only works for it, and its account uses that address" do
    inv = invitation(email: "Invited@Example.com", name: "Invited Person")
    get join_path(inv.token)
    assert_select "input[disabled][value='invited@example.com']"
    assert_select "input[name=name][value='Invited Person']"

    sign_in create_user("someone@example.com")
    get join_path(inv.token)
    assert_select "h1", text: "This invitation is for someone else"
    post accept_join_path(inv.token)
    assert_equal 0, inv.reload.uses_count

    delete session_path
    post account_join_path(inv.token), params: { email_address: "other@example.com", name: "X", password: PASSWORD, password_confirmation: PASSWORD }
    assert User.exists?(email_address: "invited@example.com")
    assert_not User.exists?(email_address: "other@example.com")
  end

  test "unknown, expired and revoked links get the same answer, and an existing address is sent to sign in" do
    get join_path("nope")
    assert_response :not_found
    expired = invitation
    expired.update!(expires_at: 1.minute.ago)
    get join_path(expired.token)
    assert_response :not_found
    revoked = invitation
    revoked.update!(revoked_at: Time.current)
    post account_join_path(revoked.token), params: { email_address: "x@example.com", name: "X", password: PASSWORD, password_confirmation: PASSWORD }
    assert_response :not_found
    assert_not User.exists?(email_address: "x@example.com")

    inv = invitation
    post account_join_path(inv.token), params: { email_address: "owner@example.com", name: "X", password: PASSWORD, password_confirmation: PASSWORD }
    assert_redirected_to join_path(inv.token)
    assert_match "already an account", flash[:alert]
    assert_equal 0, inv.reload.uses_count
  end

  test "an aircraft's manager invites to it from its Access page, emailed, with only roles they can give" do
    sign_in @owner
    assert_emails 1 do
      perform_enqueued_jobs do
        post aircraft_invitations_path(@a), params: { email: "Mech@Example.com", role_id: Role.for_key("mechanic").id, max_uses: 1, expires_at: "" }
      end
    end
    assert_response :success
    link = join_link_in(response.body)
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, link
    assert_equal [ "mech@example.com" ], ActionMailer::Base.deliveries.last.to
    inv = AccessInvitation.last
    assert_equal "Invitation to N12345", inv.label
    get aircraft_aircraft_roles_path(@a)
    assert_select "#invitations li", 1
    assert_select "#invitations select[name=role_id] option", text: "Owner"

    partner_role = Role.create!(name: "Partner", permissions: %w[manage_people])
    partner = create_user("partner@example.com")
    @a.roles.create!(user: partner, role: partner_role)
    sign_in partner
    post aircraft_invitations_path(@a), params: { role_id: Role.owner.id, max_uses: 1 }
    assert_equal 1, AccessInvitation.count
    delete aircraft_invitation_path(@a, inv)
    assert inv.reload.revoked?

    viewer = create_user("viewer@example.com")
    @a.roles.create!(user: viewer, role: "viewer")
    sign_in viewer
    post aircraft_invitations_path(@a), params: { role_id: Role.for_key("viewer").id, max_uses: 1 }
    assert_equal 1, AccessInvitation.count
  end

  test "an invitation can't give more than its creator can when it's used" do
    partner_role = Role.create!(name: "Partner", permissions: %w[manage_people])
    partner = create_user("partner@example.com")
    @a.roles.create!(user: partner, role: partner_role)
    inv = invitation(creator: partner, grants: [ [ @a, "pilot" ] ])
    @a.roles.find_by(user: partner).update!(role: "viewer") # no longer manages people

    newbie = create_user("newbie@example.com")
    sign_in newbie
    post accept_join_path(inv.token)
    assert_nil newbie.role_for(@a)
    assert_match "N12345:", flash[:notice]
  end

  test "an invitation of someone else's aircraft can't be revoked from another aircraft's page" do
    inv = invitation(grants: [ [ @b, "pilot" ] ])
    sign_in @owner
    delete aircraft_invitation_path(@a, inv)
    assert_response :not_found
    assert_not inv.reload.revoked?
  end

  test "only an administrator's invitation makes new accounts; an owner's is for existing accounts" do
    owners = invitation(creator: @owner, grants: [ [ @a, "pilot" ] ])
    get join_path(owners.token)
    assert_select "form[action=?]", account_join_path(owners.token), 0
    assert_includes response.body, "This invitation is for an existing account"
    post account_join_path(owners.token), params: { email_address: "new@example.com", name: "X", password: PASSWORD, password_confirmation: PASSWORD }
    assert_not User.exists?(email_address: "new@example.com")
    assert_equal 0, owners.reload.uses_count

    existing = create_user("existing@example.com")
    sign_in existing
    post accept_join_path(owners.token)
    assert_equal "pilot", existing.role_for(@a).key
  end

  test "an administrator's invitation stops making accounts once its creator isn't an administrator" do
    inv = invitation
    @admin.update!(admin: false)
    post account_join_path(inv.token), params: { email_address: "new@example.com", name: "X", password: PASSWORD, password_confirmation: PASSWORD }
    assert_not User.exists?(email_address: "new@example.com")
  end
end

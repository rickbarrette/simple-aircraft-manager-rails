require "test_helper"

class UserCertificatesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @owner = create_user("owner@example.com")
    @owner.update!(name: "Sam Mechanic")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
  end

  test "users add and remove their own certificates" do
    sign_in @owner
    get edit_profile_path
    assert_select "#certificates select[name='user_certificate[kind]'] option[value=IA]"
    post certificates_path, params: { user_certificate: { kind: "AP", number: " 7654321 " } }
    post certificates_path, params: { user_certificate: { kind: "IA", number: "7654321", expires_on: "2027-03-31" } }
    post certificates_path, params: { user_certificate: { kind: "BOGUS", number: "" } }
    assert_match "Certificate not added", flash[:alert]
    assert_equal [ [ "IA", "7654321" ], [ "AP", "7654321" ] ], @owner.certificates.reload.map { [ _1.kind, _1.number ] } # IA first

    other = create_user("other@example.com")
    theirs = other.certificates.create!(kind: "PILOT", number: "1111111")
    delete certificate_path(theirs)
    assert_response :not_found
    delete certificate_path(@owner.certificates.find_by!(kind: "AP"))
    assert_equal [ "IA" ], @owner.certificates.reload.map(&:kind)

    sign_in create_user("admin@example.com", admin: true)
    get admin_users_path
    assert_includes response.body, "IA 7654321"
  end

  test "Sign as fills the logbook entry and squawk resolution from the user's certificates" do
    @owner.certificates.create!(kind: "AP", number: "7654321")
    @owner.certificates.create!(kind: "IA", number: "7654321", expires_on: 1.day.ago.to_date) # expired: not offered
    sign_in @owner
    get new_aircraft_logbook_entry_path(@a)
    assert_select "form[data-controller='entry-template signer component-times']"
    assert_select "select[data-signer-target=choice] option[data-kind=AP][data-number='7654321'][data-name='Sam Mechanic']"
    assert_select "select[data-signer-target=choice] option[data-kind=IA]", 0
    assert_select "input[name='logbook_entry[signoff_person]'][data-signer-target=name]"
    assert_select "select[name='logbook_entry[signoff_certificate_type]'][data-signer-target=kind][data-entry-template-target=certificate]"

    squawk = @a.squawks.create!(priority: 1, issue_reported: "Nav light out")
    get resolution_aircraft_squawk_path(@a, squawk)
    assert_select "[data-controller='signer component-times'] select[data-signer-target=choice]"
    get deferral_aircraft_squawk_path(@a, squawk)
    assert_select "select[name=deferred_by_role] option[selected][value=mechanic]"

    nobody = create_user
    @a.roles.create!(user: nobody, role: "owner")
    sign_in nobody
    get new_aircraft_logbook_entry_path(@a)
    assert_select "select[data-signer-target=choice]", 0 # no certificates, no picker
  end

  test "an expiring certificate is in the weekly reminder, even with nothing else due" do
    @owner.certificates.create!(kind: "IA", number: "7654321", expires_on: 30.days.from_now.to_date)
    @owner.certificates.create!(kind: "PILOT", number: "1111111", expires_on: 2.years.ago.to_date) # long lapsed: not repeated
    assert_emails 1 do
      WeeklyReminderJob.perform_now
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal "Certificate expiring", mail.subject
    body = mail.text_part.body.to_s
    assert_includes body, "A&P with Inspection Authorization 7654321"
    refute_includes body, "1111111"
  end
end

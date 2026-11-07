require "test_helper"

# Expiring parts and documents, the standard inspection set, and the weekly
# reminder email.
class MaintenanceTrackingTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
  end

  test "an expired ELT battery grounds; other expiring parts and documents warn; an expired registration grounds" do
    battery = create_component(@a, component_type: component_type("ELT Battery"), replacement_critical: true, expires_on: 10.days.from_now.to_date)
    assert_equal [ "ORANGE", "ELT Battery - Expires Soon" ], [ @a.reload.airworthiness.status, @a.airworthiness.issues.sole.title ]
    battery.update!(expires_on: 1.day.ago.to_date)
    assert_equal "ELT Battery - Expired", @a.reload.airworthiness.issues.sole.title
    assert @a.airworthiness.red?
    battery.update!(expires_on: Date.current) # usable through the marked date
    refute @a.reload.airworthiness.red?
    battery.update!(expires_on: 5.years.from_now.to_date)

    insurance = @a.documents.create!(name: "Insurance", doc_type: "INSURANCE", expires_on: 1.day.ago.to_date)
    aw = @a.reload.airworthiness
    assert_equal [ "ORANGE", "Insurance - Expired" ], [ aw.status, aw.issues.sole.title ]
    insurance.destroy!
    registration = @a.documents.create!(name: "Registration", doc_type: "REGISTRATION", expires_on: 60.days.from_now.to_date)
    assert_equal "Registration - Expires Soon", @a.reload.airworthiness.issues.sole.title # 90-day warning
    registration.update!(expires_on: 1.day.ago.to_date)
    assert @a.reload.airworthiness.red?
    assert_match "91.203", @a.airworthiness.issues.sole.description

    sign_in @owner
    get aircraft_documents_path(@a)
    assert_select ".badge-red", text: /Expired/
    patch aircraft_component_path(@a, battery), params: { component: { expires_on: "2030-06-30" } }
    assert_equal Date.new(2030, 6, 30), battery.reload.expires_on
  end

  test "standard inspections add the right rules once, linking the annual to the 100-hour" do
    InspectionType.create!(name: "Transponder & encoder", recurring: true, recurring_months: 24).aircraft << @a
    sign_in @owner
    get new_aircraft_standard_inspections_path(@a)
    assert_select "input[type=checkbox][value=transponder][disabled]"
    assert_includes response.body, "Already tracked as “Transponder &amp; encoder”"

    post aircraft_standard_inspections_path(@a), params: { templates: %w[annual hundred transponder pitot_static elt vor] }
    assert_redirected_to aircraft_inspections_path(@a)
    types = @a.reload.inspection_types.index_by(&:name)
    assert_equal 6, types.size # five added, the existing transponder kept
    hundred = types["100-hour inspection (91.409(b))"]
    assert_equal [ 100, 10 ], [ hundred.recurring_hours.to_i, hundred.hours_tolerance.to_i ]
    assert_equal hundred, types["Annual inspection (91.409(a))"].satisfies
    assert_equal [ "no_ifr", 24 ], types["Altimeter and static system check (91.411)"].then { [ _1.effect, _1.recurring_months ] }
    assert_equal [ "no_ifr", 30 ], types["VOR check (91.171)"].then { [ _1.effect, _1.recurring_days ] }

    other = create_aircraft(owner: @owner)
    StandardInspections.add!(other, %w[annual])
    assert_equal types["Annual inspection (91.409(a))"], other.inspection_types.sole # shared, not duplicated
    post aircraft_standard_inspections_path(@a), params: { templates: %w[annual] }
    assert_redirected_to new_aircraft_standard_inspections_path(@a)
  end

  test "weekly reminders go to owners with something due, not to those who opted out" do
    annual = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12).tap { _1.aircraft << @a }
    @a.inspection_records.create!(inspection_type: annual, date: 13.months.ago.to_date)
    @a.squawks.create!(priority: 2, issue_reported: "Nav light inop", deferred_at: Time.current, deferred_by_name: "J",
                       deferred_by_role: "pilot", deferral_action: "deactivated")
    quiet = create_user("quiet@example.com")
    create_aircraft(owner: quiet) # nothing due
    opted_out = create_user("optout@example.com")
    opted_out.update!(reminder_emails: false)
    @a.roles.create!(user: opted_out, role: "owner")

    assert_emails 1 do
      WeeklyReminderJob.perform_now
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ [ "owner@example.com" ], "1 item overdue: N12345" ], [ mail.to, mail.subject ]
    body = mail.text_part.body.to_s
    assert_includes body, "Overdue: Annual - Overdue"
    assert_includes body, "Deferred: Inoperative: Nav light inop"

    sign_in @owner
    patch profile_path, params: { user: { reminder_emails: "0" } }
    refute @owner.reload.reminder_emails?
    assert_no_emails { WeeklyReminderJob.perform_now }

    admin = create_user("admin@example.com", admin: true)
    @a.roles.create!(user: admin, role: "owner")
    sign_in admin
    assert_emails 1 do
      post admin_test_reminder_path
    end
    assert_equal "Reminder sent to admin@example.com.", flash[:notice]
  end
end

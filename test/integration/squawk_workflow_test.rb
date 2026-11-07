require "test_helper"

# Deferring inoperative equipment (91.213(d)) and recording a squawk's fix
# in the logbook (43.9).
class SquawkWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot)
    @squawk = @a.squawks.create!(priority: 0, issue_reported: "Left landing light inop", reported_by: @pilot)
  end

  test "a pilot defers an inoperative item once every 91.213(d) condition is confirmed" do
    assert @a.reload.airworthiness.red?
    sign_in @pilot
    get aircraft_squawks_path(@a)
    assert_select "a[href='#{deferral_aircraft_squawk_path(@a, @squawk)}']", text: "Defer"
    get deferral_aircraft_squawk_path(@a, @squawk)
    assert_select "input[name='checks[]']", Squawk::DEFERRAL_CHECKS.size

    patch defer_aircraft_squawk_path(@a, @squawk), params: { checks: Squawk::DEFERRAL_CHECKS.keys.first(3),
      deferral_action: "deactivated", deferred_by_name: "Jane Pilot", deferred_by_role: "pilot" }
    assert_response :unprocessable_entity
    assert_includes response.body, "Confirm: A pilot or certificated mechanic has determined"
    refute @squawk.reload.deferred?

    patch defer_aircraft_squawk_path(@a, @squawk), params: { checks: Squawk::DEFERRAL_CHECKS.keys,
      deferral_action: "deactivated", deferred_by_name: "Jane Pilot", deferred_by_role: "pilot", deferral_notes: "Breaker collared" }
    assert_redirected_to aircraft_squawks_path(@a)
    @squawk.reload
    assert [ @squawk.deferred?, !@squawk.grounding? ].all?
    assert_equal "Deferred (91.213(d))", @squawk.priority_label
    aw = @a.reload.airworthiness
    assert_equal "GREEN", aw.status # listed, but no longer grounding
    assert_equal [ "INFO", "Inoperative: Left landing light inop" ], [ aw.issues.sole.severity, aw.issues.sole.title ]

    patch undefer_aircraft_squawk_path(@a, @squawk) # only owners undo
    assert @squawk.reload.deferred?
    sign_in @owner
    patch undefer_aircraft_squawk_path(@a, @squawk)
    refute @squawk.reload.deferred?
    assert @a.reload.airworthiness.red?
  end

  test "resolving records the fix as a logbook entry, links an existing one, or neither" do
    sign_in @owner
    get resolution_aircraft_squawk_path(@a, @squawk)
    assert_select "textarea[name='logbook_entry[text]']", text: /Corrected: Left landing light inop/

    patch resolve_aircraft_squawk_path(@a, @squawk), params: { logbook: "new", logbook_entry: {
      date: "2026-11-01", log_type: "AC", text: "Replaced left landing light lamp P/N 4509", aircraft_hours_at_entry: 1000,
      signoff_person: "Sam Mechanic", signoff_certificate_type: "AP", signoff_certificate_number: "7654321" } }
    assert_redirected_to aircraft_squawks_path(@a)
    entry = @squawk.reload.logbook_entry
    assert @squawk.resolved?
    assert_equal [ "MAINTENANCE", "AP", "7654321", [] ], [ entry.entry_type, entry.signoff_certificate_type, entry.signoff_certificate_number, entry.missing_record_items ]
    get aircraft_squawks_path(@a)
    assert_select "a[href='#{aircraft_logbook_entry_path(@a, entry)}']", text: "Logbook 2026-11-01"

    other = @a.squawks.create!(priority: 2, issue_reported: "Chipped paint")
    patch resolve_aircraft_squawk_path(@a, other), params: { logbook: "existing", logbook_entry_id: entry.id }
    assert_equal entry, other.reload.logbook_entry
    third = @a.squawks.create!(priority: 3, issue_reported: "Not a defect")
    patch resolve_aircraft_squawk_path(@a, third), params: { logbook: "none", resolution_notes: "Normal for type" }
    assert [ third.reload.resolved?, third.logbook_entry.nil? ].all?

    bad = @a.squawks.create!(priority: 1, issue_reported: "Bad")
    patch resolve_aircraft_squawk_path(@a, bad), params: { logbook: "new", logbook_entry: { date: "", text: "" } }
    assert_response :unprocessable_entity
    refute bad.reload.resolved?
  end
end

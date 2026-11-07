require "test_helper"

# Recordkeeping procedures, QC audits and user instructions (AC 120-78B 2.2.11, 3.2.8).
class RecordkeepingProceduresTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @admin = create_user("admin@example.com", admin: true)
    @a = create_aircraft(owner: @admin, tail_number: "N12345")
  end

  def fill_policy
    patch admin_procedures_path, params: { recordkeeping_policy: {
      operator_name: "Jane Pilot", responsible_name: "Jane Pilot", responsible_title: "Owner",
      hosting_description: "Self-hosted server behind a firewall.", offsite_backup_description: "Nightly encrypted off-site copy.",
      audit_interval_months: 6, audit_sample_size: 3 } }
  end

  test "admins fill in the details, preview the draft and adopt numbered, unchangeable revisions" do
    sign_in @admin
    get admin_procedures_path
    assert_response :success
    post adopt_admin_procedures_path, params: { summary: "Initial issue" }
    assert_equal 0, ProceduresRevision.count # incomplete details
    fill_policy
    assert RecordkeepingPolicy.current.complete?
    get draft_admin_procedures_path
    assert_response :success
    assert_includes response.body, "Jane Pilot"
    assert_includes response.body, "Self-hosted server behind a firewall."
    RecordkeepingPolicy.current.update!(hosting_description: "First paragraph.\n\nSecond paragraph.", additional_procedures: "**Who makes entries.** The owner.\n\n**Retention.** Kept.")
    get draft_admin_procedures_path
    assert_select ".markdown p", text: "Second paragraph."
    assert_select ".markdown strong", text: "Retention."
    assert_no_match(/\*\*Retention/, response.body)
    fill_policy
    post adopt_admin_procedures_path, params: { summary: "Initial issue" }
    r1 = ProceduresRevision.current
    assert_equal 1, r1.number
    assert_includes r1.content, "Initial issue"
    post adopt_admin_procedures_path, params: { summary: "Added a mechanic" }
    assert_equal 2, ProceduresRevision.current.number
    get revision_admin_procedures_path(r1)
    assert_includes response.body, "Jane Pilot"
    assert_raises(ActiveRecord::RecordNotSaved) { r1.update!(content: "x") }
    get admin_about_path
    assert_includes response.body, "Revision 2"
  end

  test "non-admins can't reach procedures or audits" do
    sign_in create_user("pilot@example.com")
    get admin_procedures_path
    assert_response :redirect
    get new_admin_audit_path
    assert_response :redirect
  end

  test "an audit combines the app's checks with the auditor's answers and sets the next due date" do
    sign_in @admin
    e = @a.logbook_entries.create!(date: Date.new(2026, 10, 1), entry_type: "MAINTENANCE", text: "Changed oil", aircraft_hours_at_entry: 1000)
    assert AuditRun.due_soon? # never audited
    get new_admin_audit_path
    assert_response :success
    assert_includes response.body, "Changed oil"
    assert_includes response.body, "admin@example.com"
    answers = RecordsAudit::MANUAL.keys.index_with { { passed: "1", note: "ok" } }
    post admin_audits_path, params: { answers: answers, notes: "All good", sample_ids: [ e.id ] }
    run = AuditRun.latest
    assert_redirected_to admin_audit_path(run)
    refute run.passed # no integrity check or backup has run yet
    assert run.results.find { _1["key"] == "restore_test" }["passed"]
    assert_includes run.results.find { _1["key"] == "sample_entries" }["detail"], "N12345"
    assert_equal (run.performed_at + 6.months).to_date, AuditRun.next_due
    refute AuditRun.due_soon?
    get admin_audit_path(run)
    assert_includes response.body, "All good"
    assert_raises(ActiveRecord::RecordNotSaved) { run.update!(notes: "x") }

    IntegrityCheck.create!(ok: true, problems: [])
    BackupRun.create!(ok: true, message: "ok", path: "x")
    fill_policy
    post adopt_admin_procedures_path
    post admin_audits_path, params: { answers: answers, sample_ids: [] }
    assert AuditRun.latest.passed
  end

  test "admins get a reminder when an audit is coming due" do
    assert ReminderMailer.anything_for?(@admin)
    mail = ReminderMailer.weekly(@admin)
    assert_includes mail.subject, "Records audit due"
    assert_includes mail.text_part.body.to_s, "/admin/audits/new"
    refute ReminderMailer.audit_due_for?(create_user("pilot@example.com"))
  end

  test "the records package includes the adopted procedures, and users have instructions" do
    sign_in @admin
    fill_policy
    post adopt_admin_procedures_path
    path = Rails.root.join("tmp", "package-test-#{SecureRandom.hex(4)}.zip")
    RecordsPackage.new(@a, source: "test").write_to(path)
    names = Zip::File.open(path) { |z| z.map(&:name) }
    File.delete(path)
    assert_includes names, "recordkeeping-procedures.html"
    get records_help_path
    assert_response :success
  end
end

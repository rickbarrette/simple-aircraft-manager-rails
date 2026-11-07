require "test_helper"

# 43.9 / 43.11 logbook fields, structured AD compliance (91.417(a)(2)(v)) and
# the maintenance status report (91.417(a)(2)).
class RecordKeepingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, serial_number: "17200001", make: "Cessna", model: "172N")
  end

  test "logbook entries record the signer's certificate and an inspection's result, and show what's missing" do
    sign_in @owner
    post aircraft_logbook_entries_path(@a), params: { logbook_entry: {
      date: "2026-10-01", log_type: "AC", entry_type: "INSPECTION", text: "Annual inspection IAW Part 43 App. D",
      aircraft_hours_at_entry: 1000, signoff_person: "Jane Mechanic" } }
    entry = @a.logbook_entries.last
    assert_equal [ "kind of certificate", "certificate number", "airworthiness result" ], entry.missing_record_items
    get aircraft_logbook_entries_path(@a)
    assert_select ".badge-orange[title*='certificate number']", text: "Incomplete"
    get aircraft_logbook_entry_path(@a, entry)
    assert_includes response.body, "Missing for 43.11: kind of certificate, certificate number, and airworthiness result."

    patch aircraft_logbook_entry_path(@a, entry), params: { logbook_entry: {
      signoff_certificate_type: "IA", signoff_certificate_number: " 1234567 ", inspection_result: "approved" } }
    entry.reload
    assert_equal [ [], "1234567", "A&P with Inspection Authorization" ], [ entry.missing_record_items, entry.signoff_certificate_number, entry.certificate_label ]
    get aircraft_logbook_entry_path(@a, entry)
    assert_includes response.body, "Airworthy, approved for return to service"

    flight = @a.logbook_entries.create!(date: Date.current, text: "Test flight", entry_type: "FLIGHT")
    assert_empty flight.missing_record_items # 43.9 / 43.11 don't cover these
    refute @a.logbook_entries.new(date: Date.current, text: "x", signoff_certificate_type: "BOGUS").valid?
  end

  test "AD compliance records the method and the revision; the method sets the closing flags" do
    ad = AirworthinessDirective.create!(name: "2011-10-09", short_description: "Seat rails", recurring: true, recurring_hours: 100,
                                        effective_date: Date.new(2011, 6, 1))
    ad.aircraft << @a
    sign_in @owner
    post aircraft_ad_compliances_path(@a), params: { ad_compliance: {
      airworthiness_directive_id: ad.id, date_complied: "2026-10-01", aircraft_hours_at_compliance: 1000,
      compliance_method: "terminating", compliance_notes: "Installed secondary seat stop P/N 123 per para (g)" } }
    c = @a.ad_compliances.last
    assert_equal [ "terminating", true, false, "2011-10-09, effective 2011-06-01" ],
                 [ c.compliance_method, c.permanent?, c.not_applicable?, c.ad_revision ]

    get new_aircraft_ad_compliance_path(@a, ad_id: ad.id, not_applicable: 1)
    assert_select "select[name='ad_compliance[compliance_method]'] option[selected][value=not_applicable]"
    na = @a.ad_compliances.create!(airworthiness_directive: ad, date_complied: Date.current, compliance_method: "not_applicable",
                                   compliance_notes: "S/N outside effectivity", ad_revision: "2011-10-09 R1")
    assert [ na.not_applicable?, na.closed? ].all?
    assert_equal "2011-10-09 R1", na.ad_revision

    legacy = @a.ad_compliances.new(airworthiness_directive: ad, date_complied: Date.current, compliance_notes: "x", permanent: true)
    legacy.valid?
    assert_equal "terminating", legacy.compliance_method # inferred from the old flags
    get aircraft_airworthiness_directives_path(@a)
    assert_includes response.body, "Terminating action (no further action) · 2011-10-09, effective 2011-06-01"
  end

  test "the maintenance status report covers 91.417(a)(2), for crew and maintenance share links only" do
    engine = create_component(@a, component_type: component_type("Engine"), serial_number: "L-12345-27A",
                                  hours_in_service: 3200, hours_since_overhaul: 850, tbo_hours: 2000, tbo_critical: false,
                                  overhaul_date: Date.new(2019, 5, 1))
    create_component(@a, component_type: component_type("ELT Battery"), model: "E-04", manufacturer: "ACK",
                         replacement_critical: true, replacement_days: 730, overhaul_date: 1.year.ago.to_date)
    annual = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12).tap { _1.aircraft << @a }
    @a.inspection_records.create!(inspection_type: annual, date: 2.months.ago.to_date, aircraft_hours: 990)
    ad = AirworthinessDirective.create!(name: "2020-01-01", short_description: "Muffler inspection", recurring: true, recurring_hours: 100)
    ad.aircraft << @a
    @a.ad_compliances.create!(airworthiness_directive: ad, date_complied: 1.month.ago.to_date, aircraft_hours_at_compliance: 995,
                              compliance_method: "inspection", compliance_notes: "Inspected muffler, no cracks")
    @a.major_records.create!(record_type: "alteration", title: "Garmin GTX 345 installed", date_performed: Date.new(2024, 3, 1),
                             stc_number: "SA01234WI", form_337_document: @a.documents.create!(name: "337", doc_type: "ALTER"))

    sign_in @pilot
    get aircraft_path(@a)
    assert_select "a[href='#{aircraft_report_path(@a)}']", text: "Status report"
    get aircraft_report_path(@a)
    assert_response :success
    body = response.body
    [ "Maintenance status · 14 CFR 91.417(a)(2)", "17200001", "L-12345-27A", "3,200.0", "850.0", "Recommended",
      "ELT Battery", "Annual", "Revision complied with", "Inspection", "Inspected muffler", "1,095.0 hrs",
      "Garmin GTX 345 installed", "SA01234WI", "On file", "This summary doesn't replace the aircraft's signed maintenance records" ].each do |text|
      assert_includes body, text, "missing: #{text}"
    end
    assert_select "button[data-print]", text: "Print or save as PDF"
    assert_equal engine, MaintenanceReport.new(@a).engines.sole

    sign_in create_user
    get aircraft_report_path(@a)
    assert_response :not_found

    status_link = @a.share_tokens.create!(privilege: "status")
    detail_link = @a.share_tokens.create!(privilege: "maintenance")
    delete session_path
    get shared_report_path(status_link.token)
    assert_response :not_found
    get shared_path(detail_link.token)
    assert_select "a[href='#{shared_report_path(detail_link.token)}']"
    get shared_report_path(detail_link.token)
    assert_response :success
    assert_includes response.body, "L-12345-27A"
  end
end

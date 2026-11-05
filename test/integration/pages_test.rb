require "test_helper"

# Renders every page with realistic data to catch view/route errors.
class PagesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com", admin: false)
    @a = create_aircraft(owner: @owner, tail_number: "N100AB")
    @engine = create_component(@a)
    @oil = create_component(@a, component_type: component_type("Oil"), parent_component: @engine,
                            replacement_critical: true, replacement_hours: 50, hours_since_overhaul: 45, overhaul_date: Date.current)
    @squawk = @a.squawks.create!(priority: 1, issue_reported: "Nav light out", reported_by: @owner)
    @a.squawks.create!(priority: 3, issue_reported: "Old one", resolved: true, resolved_at: Time.current)
    @note = @a.notes.create!(text: "Hangar 4", user: @owner, public: true)
    @entry = @a.logbook_entries.create!(date: Date.current, text: "Oil changed", aircraft_hours_at_entry: 1000)
    @collection = @a.document_collections.create!(name: "Logbooks", visibility: "status")
    @doc = @a.documents.create!(name: "W&B", document_collection: @collection)
    @doc.pages.attach(io: StringIO.new("hello"), filename: "wb.txt", content_type: "text/plain")
    @itype = InspectionType.create!(name: "Annual", recurring: true, recurring_months: 12)
    @itype.aircraft << @a
    @irec = @a.inspection_records.create!(inspection_type: @itype, date: Date.current, aircraft_hours: 1000)
    @ad = AirworthinessDirective.create!(name: "2020-01-01", short_description: "Check", recurring: true, recurring_hours: 100)
    @ad.aircraft << @a
    @adc = @ad.ad_compliances.create!(aircraft: @a, date_complied: Date.current, compliance_notes: "Done", next_due_at_time: 1100)
    @major = @a.major_records.create!(record_type: "alteration", title: "LED lights", date_performed: Date.current)
    @flight = @a.flight_logs.create!(date: Date.current, tach_time: 1.2)
    @cr = @a.consumable_records.create!(record_type: "oil", date: Date.current, quantity_added: 1, flight_hours: 1000)
    @token = @a.share_tokens.create!(privilege: "maintenance", label: "Mechanic")
    @a.log_event!("aircraft", "Created", user: @owner)
    sign_in @owner
  end

  test "owner can render every page" do
    a = @a
    paths = [
      root_path, aircraft_path(a), new_aircraft_path, edit_aircraft_path(a),
      aircraft_components_path(a), aircraft_components_path(a, disposed: 1), new_aircraft_component_path(a),
      aircraft_component_path(a, @engine), edit_aircraft_component_path(a, @oil),
      aircraft_squawks_path(a), new_aircraft_squawk_path(a), edit_aircraft_squawk_path(a, @squawk),
      aircraft_notes_path(a), new_aircraft_note_path(a), edit_aircraft_note_path(a, @note),
      aircraft_flight_logs_path(a), new_aircraft_flight_log_path(a), aircraft_flight_log_path(a, @flight),
      aircraft_consumable_records_path(a), new_aircraft_consumable_record_path(a, type: "fuel"), edit_aircraft_consumable_record_path(a, @cr),
      aircraft_logbook_entries_path(a), aircraft_logbook_entries_path(a, q: "oil", log_type: "AC"),
      new_aircraft_logbook_entry_path(a), aircraft_logbook_entry_path(a, @entry), edit_aircraft_logbook_entry_path(a, @entry),
      aircraft_documents_path(a), new_aircraft_document_path(a), aircraft_document_path(a, @doc), edit_aircraft_document_path(a, @doc),
      new_aircraft_document_collection_path(a), edit_aircraft_document_collection_path(a, @collection),
      aircraft_inspections_path(a), new_aircraft_inspection_type_path(a), edit_aircraft_inspection_type_path(a, @itype),
      new_aircraft_inspection_record_path(a, inspection_type_id: @itype.id), edit_aircraft_inspection_record_path(a, @irec),
      aircraft_airworthiness_directives_path(a), new_aircraft_airworthiness_directive_path(a),
      edit_aircraft_airworthiness_directive_path(a, @ad), new_aircraft_ad_compliance_path(a, ad_id: @ad.id),
      edit_aircraft_ad_compliance_path(a, @adc),
      aircraft_major_records_path(a), new_aircraft_major_record_path(a), aircraft_major_record_path(a, @major),
      edit_aircraft_major_record_path(a, @major),
      aircraft_aircraft_roles_path(a), aircraft_events_path(a), aircraft_events_path(a, category: "aircraft"),
      edit_profile_path
    ]
    paths.each do |path|
      get path
      assert_response :success, "GET #{path} → #{response.status}"
    end
  end

  test "AD compliance form is prefilled from the AD's recurrence" do
    get new_aircraft_ad_compliance_path(@a, ad_id: @ad.id)
    assert_select "input[name='ad_compliance[next_due_at_time]'][value='1100.0']"
    assert_select "form[data-controller='next-due'][data-next-due-rules-value*='\"#{@ad.id}\"']"
    get new_aircraft_inspection_record_path(@a, inspection_type_id: @itype.id)
    assert_select "form[data-controller='next-due'][data-next-due-rules-value*='\"months\":12']"
  end

  test "compliance history shows the AD's description and links" do
    @ad.update!(document_url: "https://drs.faa.gov/browse/excelExternalWindow/ABC.0001")
    @adc.update!(logbook_entry: @entry)
    get aircraft_airworthiness_directives_path(@a)
    assert_select "section", text: /Compliance History/ do
      assert_select "a[href='https://drs.faa.gov/browse/excelExternalWindow/ABC.0001'][target='_blank']", text: "2020-01-01"
      assert_select "div", text: "Check"
      assert_select "a[href='#{aircraft_logbook_entry_path(@a, @entry)}']"
    end

    delete session_path
    get shared_path(@token.token)
    assert_select "a[href='https://drs.faa.gov/browse/excelExternalWindow/ABC.0001']", minimum: 2 # status + history
  end

  test "maintenance share link renders without login and shows history" do
    delete session_path
    get shared_path(@token.token)
    assert_response :success
    assert_includes response.body, "N100AB"
    assert_includes response.body, "Oil changed"   # logbook
    assert_includes response.body, "LED lights"    # major records
    assert_includes response.body, "Hangar 4"      # public note
    assert_includes response.body, "W&amp;B"       # status-visible doc
  end

  test "status share link hides maintenance history" do
    t = @a.share_tokens.create!(privilege: "status")
    @a.notes.create!(text: "Secret combo", public: false)
    delete session_path
    get shared_path(t.token)
    assert_response :success
    assert_not_includes response.body, "Oil changed"
    assert_not_includes response.body, "LED lights"
    assert_not_includes response.body, "Secret combo"
    assert_includes response.body, "Nav light out"
  end

  test "expired or unknown share link is 404" do
    t = @a.share_tokens.create!(privilege: "status", expires_at: 1.minute.ago)
    get shared_path(t.token)
    assert_response :not_found
    get shared_path("nope")
    assert_response :not_found
  end

  test "admin pages" do
    admin = create_user("boss@example.com", admin: true)
    sign_in admin
    [ admin_users_path, new_admin_user_path, edit_admin_user_path(@owner),
      admin_component_types_path, new_admin_component_type_path ].each do |path|
      get path
      assert_response :success, path
    end
    get aircraft_path(@a) # admins see every aircraft
    assert_response :success
  end
end

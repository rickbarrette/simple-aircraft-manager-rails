require "test_helper"

# ADs and inspection types are shared between aircraft; linking, unlinking
# and changing them is kept in each aircraft's record history.
class AdHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @a = create_aircraft(owner: @owner, tail_number: "N12345")
    @engine = create_component(@a, component_type: component_type("Engine"), model: "O-200A")
    sign_in @owner
  end

  def history(event = nil)
    scope = RecordVersion.where(aircraft_id: @a.id, item_type: "AirworthinessDirective")
    event ? scope.where(event: event) : scope
  end

  test "applying, changing, removing and restoring an AD are all in the history, with who did it" do
    post aircraft_airworthiness_directives_path(@a), params: { applies_to_airframe: "1",
      airworthiness_directive: { name: "2000-06-01", bulletin_type: "ad", compliance_type: "standard", short_description: "Fuel strainer" } }
    ad = AirworthinessDirective.find_by!(name: "2000-06-01")
    assert_equal [ "airframe" ], history("link").map { _1.changes_hash["applies_to"] }
    assert_equal @owner, history("link").last.user

    patch aircraft_airworthiness_directive_path(@a, ad), params: { applies_to_airframe: "0", component_ids: [ @engine.id ],
      airworthiness_directive: { short_description: "Fuel strainer assembly" } }
    assert_equal [ "Fuel strainer", "Fuel strainer assembly" ], history("update").last.changes_hash["short_description"]
    assert_equal "component", history("link").last.changes_hash["applies_to"]
    assert_equal "airframe", history("unlink").last.changes_hash["applies_to"]

    delete aircraft_airworthiness_directive_path(@a, ad) # removed from this aircraft (no compliance: the AD record goes too)
    assert_equal "component", history("unlink").last.changes_hash["applies_to"]

    ad2 = AirworthinessDirective.create!(name: "71-22-02", short_description: "Nose gear fork")
    ad2.aircraft << @a
    ad2.ad_compliances.create!(aircraft: @a, date_complied: Date.current, compliance_method: "inspection", compliance_notes: "Inspected, no cracks")
    delete aircraft_airworthiness_directive_path(@a, ad2)
    refute_includes @a.reload.applicable_ads, ad2
    unlink = history("unlink").where(item_id: ad2.id).last
    get aircraft_record_versions_path(@a)
    assert_select "button", text: "Restore"
    assert_includes response.body, "71-22-02 no longer applies to the airframe"

    post restore_aircraft_record_version_path(@a, unlink)
    assert_includes @a.reload.applicable_ads, ad2
    assert_equal 2, history("link").where(item_id: ad2.id).count # the restore is a new link
    assert RecordsIntegrity.check!.ok # the chain still verifies
  end

  test "deleting a component records that its ADs no longer apply; DRS-style links are recorded too" do
    ad = AirworthinessDirective.create!(name: "96-12-22", short_description: "Oil adapter")
    ad.components << @engine
    assert_equal "O-200A", history("link").last.changes_hash["component"].split.last
    delete aircraft_component_path(@a, @engine)
    assert_equal "component deleted", history("unlink").last.changes_hash["reason"]
  end

  test "pilots can't restore" do
    pilot = create_user("pilot@example.com")
    @a.roles.create!(user: pilot, role: "pilot")
    ad = AirworthinessDirective.create!(name: "68-17-04", short_description: "Stall warning")
    ad.aircraft << @a
    ad.aircraft.delete(@a)
    sign_in pilot
    post restore_aircraft_record_version_path(@a, history("unlink").last)
    refute_includes @a.reload.applicable_ads, ad
  end
end

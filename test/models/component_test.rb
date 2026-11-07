require "test_helper"

class ComponentTest < ActiveSupport::TestCase
  test "deleting a component, or its aircraft, works when records point at it" do
    a = create_aircraft
    engine = create_component(a)
    ad = AirworthinessDirective.create!(name: "2020-01-01", short_description: "Check")
    compliance = a.ad_compliances.create!(airworthiness_directive: ad, date_complied: Date.current, compliance_notes: "Done",
                                          permanent: true, component: engine)
    annual = InspectionType.create!(name: "Annual")
    record = a.inspection_records.create!(inspection_type: annual, date: Date.current, component: engine)

    engine.destroy!
    assert_nil compliance.reload.component_id
    assert_nil record.reload.component_id

    other = create_component(a)
    a.ad_compliances.create!(airworthiness_directive: ad, date_complied: Date.current, compliance_notes: "Done", permanent: true, component: other)
    a.inspection_records.create!(inspection_type: annual, date: Date.current, component: other)
    a.destroy!
    assert_not Aircraft.exists?(a.id)
  end
end

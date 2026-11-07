require "test_helper"

class AdImportFlowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @pilot = create_user
    @aircraft = create_aircraft(owner: @owner, pilot: @pilot, model: "150L")
  end

  test "owner uploads, reviews, and imports" do
    sign_in @owner
    get aircraft_airworthiness_directives_path(@aircraft)
    assert_select "a[href='#{new_aircraft_ad_import_path(@aircraft)}']"

    post aircraft_ad_import_path(@aircraft), params: { file: fixture_file_upload("drs_ads.csv", "text/csv") }
    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_select "select[name='decisions[2011-10-09]'] option[selected][value='track']"
    assert_select "select[name='decisions[87-20-03 R2]'] option[selected][value='skip']"
    assert_match "Excel</strong> export includes them", response.body
    token = response.body[/name="token"[^>]*value="([^"]+)"/, 1]

    post confirm_aircraft_ad_import_path(@aircraft), params: {
      token: token, filename: "AD Final Rules.csv",
      decisions: { "2011-10-09" => "track", "2008-22-18" => "na", "96-12-22" => "skip", "75-15-08" => "skip", "87-20-03 R2" => "skip" }
    }
    assert_redirected_to aircraft_airworthiness_directives_path(@aircraft)
    assert_equal %w[2008-22-18 2011-10-09], @aircraft.applicable_ads.order(:name).pluck(:name)
    follow_redirect!
    assert_select "span", text: "N/A"
    # CSV exports carry no links, so the AD number isn't a link
    assert_select "a", text: "2011-10-09", count: 0
  end

  test "N/A quick action records a not-applicable determination" do
    ad = AirworthinessDirective.create!(name: "2008-22-18", short_description: "BRS")
    ad.aircraft << @aircraft
    sign_in @owner
    get new_aircraft_ad_compliance_path(@aircraft, ad_id: ad.id, not_applicable: 1)
    assert_select "select[name='ad_compliance[compliance_method]'] option[selected][value=not_applicable]"
    post aircraft_ad_compliances_path(@aircraft), params: { ad_compliance: {
      airworthiness_directive_id: ad.id, date_complied: Date.current, compliance_method: "not_applicable",
      compliance_notes: "Not applicable: no BRS parachute installed" } }
    assert_equal "GREEN", @aircraft.reload.airworthiness.status
  end

  test "pilots cannot import ADs" do
    sign_in @pilot
    post aircraft_ad_import_path(@aircraft), params: { file: fixture_file_upload("drs_ads.csv", "text/csv") }
    assert_response :redirect
    assert_equal 0, @aircraft.applicable_ads.count
  end
end

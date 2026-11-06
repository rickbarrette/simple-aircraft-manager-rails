require "test_helper"

class AdminAirportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  CSV_BODY = <<~CSV.freeze
    "id","ident","type","name","latitude_deg","longitude_deg","elevation_ft","continent","iso_country","iso_region","municipality","scheduled_service","icao_code","iata_code","gps_code","local_code","home_link","wikipedia_link","keywords"
    1,"KOQU","medium_airport","Quonset State Airport",41.597,-71.412,18,"NA","US","US-RI","North Kingstown","no","KOQU","NCO","KOQU","OQU",,,
    2,"K1B9","small_airport","Mansfield Municipal Airport",42.0,-71.19,122,"NA","US","US-MA","Mansfield","no",,,"1B9","1B9",,,
  CSV

  setup do
    @admin = create_user("admin@example.com", admin: true)
    stub_request(:get, AirportData::SOURCE_URL).to_return(status: 200, body: CSV_BODY)
  end

  test "admin updates from OurAirports in the background and sees the result" do
    sign_in @admin
    get admin_airports_path
    assert_response :success
    assert_select "details[data-controller='dropdown'] summary", text: /Admin/
    assert_select "details a[href='#{admin_airports_path}']", text: "Airports" # in the Admin menu
    assert_select "details a[href='#{admin_users_path}']", text: "Users"

    perform_enqueued_jobs { post refresh_admin_airports_path }
    assert_redirected_to admin_airports_path
    assert_equal 2, Airport.count
    update = AirportUpdate.last
    assert_equal [ "done", 2, @admin ], [ update.status, update.created_count, update.requested_by ]
    follow_redirect!
    assert_match "2 added, 0 updated, 0 removed", response.body
  end

  test "failed downloads are recorded" do
    stub_request(:get, AirportData::SOURCE_URL).to_return(status: 503)
    sign_in @admin
    perform_enqueued_jobs { post refresh_admin_airports_path }
    assert_equal "failed", AirportUpdate.last.status
    follow_redirect!
    assert_match "503", response.body
  end

  test "first start populates an empty table once" do
    assert_enqueued_jobs(1, only: AirportUpdateJob) { AirportUpdateJob.ensure_populated }
    assert_no_enqueued_jobs(only: AirportUpdateJob) { AirportUpdateJob.ensure_populated } # already queued
    perform_enqueued_jobs
    assert_equal 2, Airport.count
    assert_no_enqueued_jobs(only: AirportUpdateJob) { AirportUpdateJob.ensure_populated } # has data
  end

  test "admin manages custom airports; only custom ones are editable" do
    sign_in @admin
    get admin_airports_path(q: "0R8")
    assert_select "a[href='#{new_admin_airport_path(ident: '0R8')}']"
    post admin_airports_path, params: { airport: { ident: "0r8", name: "Grass Strip", kind: "small_airport", region: "US-RI" } }
    strip = Airport.find_by!(ident: "0R8")
    assert strip.custom?
    assert_equal "0R8", strip.airtrail_code
    patch admin_airport_path(strip), params: { airport: { name: "Grass Strip North" } }
    assert_equal "Grass Strip North", strip.reload.name

    AirportData.sync!(StringIO.new(CSV_BODY))
    get edit_admin_airport_path(Airport.find_by!(ident: "KOQU"))
    assert_response :not_found
    delete admin_airport_path(strip)
    assert_not Airport.exists?(strip.id)
  end

  test "non-admins can't reach it" do
    sign_in create_user
    get root_path
    assert_select "summary", text: /Admin/, count: 0
    get admin_airports_path
    assert_redirected_to root_path
    post refresh_admin_airports_path
    assert_equal 0, AirportUpdate.count
  end
end

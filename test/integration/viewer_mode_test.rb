require "test_helper"

# Viewer mode (SAM_VIEWER, see Viewer): what a records package's viewer runs.
# The archive is imported at start; everyone browses it read-only, without
# signing in; and it refuses to run on a database with real accounts.
class ViewerModeTest < ActionDispatch::IntegrationTest
  setup do
    @saved = ENV.values_at("SAM_VIEWER", "SAM_VIEWER_ARCHIVE", "SAM_VIEWER_INFO")
    owner = create_user("owner@example.com")
    aircraft = create_aircraft(owner: owner, tail_number: "N12345", tach_time: 1234.5)
    aircraft.squawks.create!(priority: 1, issue_reported: "Left nav light out")
    @archive = File.join(Dir.mktmpdir, "n12345.sam.zip")
    AircraftArchive::Exporter.new(aircraft).write_to(@archive)
    Aircraft.destroy_all
    User.delete_all # a fresh, empty copy, as in the viewer's own container
    ENV["SAM_VIEWER"] = "true"
    ENV["SAM_VIEWER_ARCHIVE"] = @archive
    ENV["SAM_VIEWER_INFO"] = File.join(File.dirname(@archive), "viewer.json") # this test's own (tests run in parallel)
  end

  teardown do
    ENV["SAM_VIEWER"], ENV["SAM_VIEWER_ARCHIVE"], ENV["SAM_VIEWER_INFO"] = @saved
  end

  def prepare
    out = StringIO.new
    Viewer.prepare!(output: out)
    out.string
  end

  test "the archive is imported at start, once" do
    assert_match "Viewer: imported N12345", prepare
    assert_equal [ "N12345" ], Aircraft.pluck(:tail_number)
    assert_match "already imported", prepare
    assert_equal 1, Aircraft.count
  end

  test "anyone browses it without signing in, and can't change anything" do
    prepare
    get root_path
    assert_response :success
    assert_select "#viewer-banner", text: /Read-only copy of the records in n12345\.sam\.zip/
    assert_includes response.body, "N12345"
    assert_select "a[href=?]", new_aircraft_path, 0
    assert_select "form[action=?]", session_path, 0 # no sign-out

    aircraft = Aircraft.sole
    get aircraft_path(aircraft)
    assert_response :success
    assert_select "a[href=?]", new_aircraft_flight_log_path(aircraft), 0
    assert_select "form[action=?]", hours_aircraft_path(aircraft), 0
    get aircraft_squawks_path(aircraft)
    assert_includes response.body, "Left nav light out"

    post aircraft_flight_logs_path(aircraft), params: { flight_log: { date: Date.current, tach_out: 1234.5, tach_in: 1235.5 } }
    assert_equal "This is a read-only copy of the records; nothing can be changed here.", flash[:alert]
    assert_equal 0, aircraft.flight_logs.count
    patch hours_aircraft_path(aircraft), params: { tach_time: 2000 }
    assert_equal 1234.5, aircraft.reload.tach_time
    delete session_path
    get root_path
    assert_response :success # still in
  end

  test "it refuses to run on a database with real accounts" do
    create_user("someone@example.com")
    assert_raises(Viewer::RealAccounts) { prepare }
    assert_equal 0, Aircraft.count
    get root_path
    assert_response :service_unavailable
    assert_includes response.body, "SAM_VIEWER is on, but this database has user accounts"
  end
end

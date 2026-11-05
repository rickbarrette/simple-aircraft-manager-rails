require "test_helper"
require "caxlsx"

class FlightImportTest < ActiveSupport::TestCase
  CSV_PATH = Rails.root.join("test/fixtures/files/flights.csv")

  setup do
    @user = create_user
    @aircraft = create_aircraft(owner: @user, tach_time: 7270, hobbs_time: 100)
    @engine = create_component(@aircraft, hours_in_service: 500, hours_since_overhaul: 500)
  end

  def import(path = CSV_PATH, name = "flights.csv", **opts)
    FlightImport.new(@aircraft, path: path, filename: name, **opts)
  end

  test "derives durations from consecutive readings and flags the backwards tach" do
    imp = import
    rows = imp.rows
    assert_equal 13, rows.size
    assert_equal %i[date from to tach hobbs oil fuel flight_time], imp.columns.keys

    first = rows.first
    assert_equal :warning, first.status # no starting tach → Flight Time column
    assert_equal BigDecimal("1.6"), first.tach_time
    assert_equal BigDecimal("7276.2"), first.tach_out
    assert_equal BigDecimal("14.3"), first.fuel
    assert_nil first.oil

    assert_equal BigDecimal("0.6"), rows[1].tach_time
    assert_equal BigDecimal("0.8"), rows[1].hobbs_time

    bad = rows[8] # 10/23, tach 7283.0 after 7283.2
    assert_equal :error, bad.status
    assert_match "backwards", bad.messages.first
    # the next good row absorbs the time from the last good reading
    assert_equal BigDecimal("1.3"), rows[9].tach_time
    assert_equal BigDecimal("7283.2"), rows[9].tach_out
    assert_equal BigDecimal("1.7"), rows[9].hobbs_time

    assert_equal BigDecimal("15.45"), rows[11].fuel
    assert_equal 12, imp.importable.size
    assert_equal BigDecimal("14.1"), imp.total_tach_hours # 7290.3 - 7276.2
  end

  test "starting tach makes the first row exact" do
    rows = import(starting_tach: "7276.5", starting_hobbs: "140.0").rows
    assert_equal :ok, rows.first.status
    assert_equal BigDecimal("1.3"), rows.first.tach_time
    assert_equal BigDecimal("1.3"), rows.first.hobbs_time
  end

  test "import creates flights and consumables but leaves component hours alone" do
    count = import.import!(user: @user)
    assert_equal 12, count
    assert_equal 12, @aircraft.flight_logs.count
    assert_equal 0, @aircraft.consumable_records.oil.count # the only oil row was the bad one
    assert_equal 6, @aircraft.consumable_records.fuel.count # 8.7 gal was on the skipped row
    fuel = @aircraft.consumable_records.fuel.find_by(quantity_added: 15.45)
    assert_equal BigDecimal("7289.1"), fuel.flight_hours
    assert_equal 7270, @aircraft.reload.tach_time
    assert_equal 500, @engine.reload.hours_in_service
    assert_equal 1, @aircraft.events.where(category: "flight").count
  end

  test "re-importing skips duplicates" do
    import.import!(user: @user)
    again = import
    assert_equal 12, again.count(:duplicate)
    assert_equal 1, again.count(:error)
    assert_raises(FlightImport::Error) { again.import!(user: @user) }
  end

  test "optionally advances aircraft meters to the last reading" do
    import.import!(user: @user, update_aircraft_hours: true)
    @aircraft.reload
    assert_equal BigDecimal("7290.3"), @aircraft.tach_time
    assert_equal BigDecimal("156.1"), @aircraft.hobbs_time
    assert_equal BigDecimal("520.3"), @engine.reload.hours_in_service # +20.3 like a normal hours update
  end

  test "never moves meters backwards" do
    @aircraft.update!(tach_time: 7300)
    import.import!(user: @user, update_aircraft_hours: true)
    assert_equal 7300, @aircraft.reload.tach_time
  end

  test "reads xlsx with real dates and numbers, header not on first row" do
    path = Rails.root.join("tmp/test-flights-#{SecureRandom.hex(4)}.xlsx")
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: "Log") do |ws|
      ws.add_row [ "My airplane" ]
      ws.add_row [ "Date", "From", "To", "Tach Time", "Hobbs Time", "Oil Added", "Fuel Added", "Flight Time" ]
      ws.add_row [ Date.new(2026, 10, 17), "KAAA", "KBBB", 7277.8, 141.3, "N", 14.3, 1.6 ]
      ws.add_row [ Date.new(2026, 10, 17), "KBBB", "KCCC", 7278.4, 142.1, 1, "N", 0.8 ]
    end
    pkg.serialize(path.to_s)

    rows = import(path, "log.xlsx").rows
    assert_equal 2, rows.size
    assert_equal Date.new(2026, 10, 17), rows.first.date
    assert_equal BigDecimal("0.6"), rows.last.tach_time
    assert_equal BigDecimal("1"), rows.last.oil
  ensure
    FileUtils.rm_f(path)
  end

  test "without a Flight Time column the first row is a baseline, not a cascade of errors" do
    path = Rails.root.join("tmp/nofltime-#{SecureRandom.hex(4)}.csv")
    File.write(path, <<~CSV)
      Date,From,To,Tach Time,Hobbs Time,Oil Added,Fuel Added
      11/8/21,53NH,KPVD,6704.7,11.3,1,N
      11/11/21,KPVD,KEWB,6705.2,13.5,N,Full
      11/11/21,KEWB,KPVD,6705.9,14.4,N,N
      11/13/21,KPVD,KPVD,6705.9,15.8, N,10
    CSV
    rows = import(path, "f.csv").rows
    assert_equal %i[error warning ok warning], rows.map(&:status)
    assert_equal BigDecimal("0.5"), rows[1].tach_time
    assert_nil rows[1].fuel # "Full" has no quantity
    assert_equal BigDecimal("0"), rows[3].tach_time # unchanged tach → 0.0 hr entry, fuel kept
    assert_equal BigDecimal("10"), rows[3].fuel
    assert_nil rows[3].oil # " N" with leading space

    imp = import(path, "f.csv")
    assert_equal 3, imp.import!(user: @user)
    assert_equal 1, @aircraft.consumable_records.fuel.count
  ensure
    FileUtils.rm_f(path)
  end

  test "rejects files without the required columns" do
    path = Rails.root.join("tmp/bad-#{SecureRandom.hex(4)}.csv")
    File.write(path, "Name,Value\na,1\n")
    assert_raises(FlightImport::Error) { import(path, "bad.csv").rows }
  ensure
    FileUtils.rm_f(path)
  end
end

require "test_helper"

# The Overview's Last flight and Coming due cards, and intervals entered as
# days, months or years.
class OverviewDueAndIntervalsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("owner@example.com")
    @pilot = create_user("pilot@example.com")
    @a = create_aircraft(owner: @owner, pilot: @pilot, tail_number: "N12345", tach_time: 1000)
    @a.flight_logs.create!(date: Date.current - 20, tach_time: 1.0, departure_location: "KAAA", destination_location: "KAAA")
    @a.flight_logs.create!(date: Date.current - 3, tach_time: 1.2, departure_location: "KAAA", destination_location: "KBBB")
    @a.flight_logs.create!(date: Date.current - 3, tach_time: 0.9, departure_location: "KBBB", destination_location: "KAAA",
                           tach_in: 1000, fuel_level_after: 18, oil_level_after: 5)
    @oil = create_component(@a, component_type: component_type("Oil"), manufacturer: "Phillips", model: "20W50",
                                replacement_hours: 50, hours_since_overhaul: 46, overhaul_date: Date.current - 30)
    create_component(@a, component_type: component_type("Magneto"), manufacturer: "Bendix", model: "S4LN-21",
                         replacement_hours: 500, hours_since_overhaul: 100, overhaul_date: Date.current - 30)
  end

  test "the overview shows the last day's flying and what's coming due" do
    sign_in @pilot
    get aircraft_path(@a)
    assert_response :success
    body = response.body
    assert_includes body, "KAAA → KBBB → KAAA"
    assert_includes body, "2 legs"
    assert_includes body, "18 gal"
    assert_includes body, "5 qt"
    assert_includes body, "Replace Oil" # 4 hrs left
    assert_not_includes body, "Replace Magneto" # 400 hrs left
  end

  test "the overview copes with nothing logged" do
    bare = create_aircraft(owner: @owner, tail_number: "N54321")
    sign_in @owner
    get aircraft_path(bare)
    assert_response :success
    assert_includes response.body, "No flights logged yet."
    assert_includes response.body, "Nothing coming due soon."
  end

  test "hours already run out count as overdue; an inspection covering a component replaces its own interval" do
    filter = create_component(@a, component_type: component_type("Oil Filter"), manufacturer: "Champion", model: "CH48110",
                                  inspection_hours: 50, hours_since_overhaul: 60, overhaul_date: Date.current - 300)
    mag = create_component(@a, component_type: component_type("Magneto"), manufacturer: "Slick", model: "4371",
                               inspection_hours: 500, hours_since_overhaul: 120, overhaul_date: Date.current - 300)
    items = DueList.new(@a).items.index_by(&:key)
    assert items["inspect-#{filter.id}"].overdue?
    assert_equal Date.current, items["inspect-#{filter.id}"].date
    refute items["replace-#{@oil.id}"].overdue?

    type = InspectionType.create!(name: "Oil change", effect: "advisory", recurring: true, recurring_hours: 50)
    type.components << filter
    assert_nil DueList.new(@a).items.find { _1.key == "inspect-#{filter.id}" }
    assert DueList.new(@a).items.find { _1.key == "inspect-#{mag.id}" }
  end

  test "a component limit in years is stored as months and lands on the same date" do
    sign_in @owner
    get edit_aircraft_component_path(@a, @oil)
    assert_select "select[name='component[replacement_unit]'] option", text: "years"

    patch aircraft_component_path(@a, @oil), params: { component: { replacement_every: "2", replacement_unit: "years",
                                                                    overhaul_date: "2026-03-10" } }
    @oil.reload
    assert_equal [ nil, 24 ], [ @oil.replacement_days, @oil.replacement_months ]
    assert_equal Date.new(2028, 3, 10), @oil.next_replacement_date
    assert_equal "2 years", @oil.replacement_interval_label

    get edit_aircraft_component_path(@a, @oil)
    assert_select "input[name='component[replacement_every]'][value='2']"
    assert_select "select[name='component[replacement_unit]'] option[selected]", text: "years"

    patch aircraft_component_path(@a, @oil), params: { component: { replacement_every: "90", replacement_unit: "days" } }
    assert_equal [ 90, nil ], @oil.reload.then { [ _1.replacement_days, _1.replacement_months ] }

    patch aircraft_component_path(@a, @oil), params: { component: { replacement_every: "", replacement_unit: "days" } }
    assert_equal [ nil, nil ], @oil.reload.then { [ _1.replacement_days, _1.replacement_months ] }

    patch aircraft_component_path(@a, @oil), params: { component: { replacement_every: "1.5", replacement_unit: "months" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "must be a whole number more than 0"
  end

  test "inspection types and ADs take months or years, still due at the end of the month" do
    sign_in @owner
    post aircraft_inspection_types_path(@a), params: { inspection_type: { name: "ELT check", effect: "grounds", recurring: "1",
                                                                         recurring_hours: "0", recurring_every: "1", recurring_unit: "years" },
                                                       applies_to_airframe: "1" }
    type = InspectionType.find_by!(name: "ELT check")
    assert_equal [ 12, 0 ], [ type.recurring_months, type.recurring_days ]
    assert_equal "Every 1 year", type.interval_description

    ad = AirworthinessDirective.new(name: "2020-01-01", short_description: "Seat rails", recurring: true, recurring_every: "100", recurring_unit: "days")
    ad.valid?
    assert_equal [ 100, 0 ], [ ad.recurring_days, ad.recurring_months ]
    assert_equal({ hours: 0.0, months: 0, days: 100 }, ad.due_rule)
    ad.recurring_every = "2"
    ad.recurring_unit = "years"
    ad.valid?
    assert_equal [ 0, 24 ], [ ad.recurring_days, ad.recurring_months ]
    assert_equal "2 years", ad.recurring_interval_label
  end
end

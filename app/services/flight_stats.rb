# Flying metrics for the Flights tab: totals, recent periods, fuel, airports
# and a monthly/yearly breakdown.
#
# "Flight time" is Hobbs time where the flight has it, otherwise tach time
# (e.g. flights logged before a Hobbs was installed).
class FlightStats
  Period = Struct.new(:label, :flights, :tach, :flight, :fuel, keyword_init: true)

  attr_reader :today

  def initialize(aircraft, today: Date.current)
    @aircraft = aircraft
    @today = today
    @flights = aircraft.flight_logs.order(:date, :created_at).to_a
    @fuel = aircraft.consumable_records.where(record_type: "fuel").pluck(:date, :quantity_added)
  end

  def any? = @flights.any?
  def count = @flights.size
  def first_date = @flights.first&.date

  def total_tach = sum(@flights) { _1.tach_time }
  def total_flight = sum(@flights) { flight_hours(_1) }
  def total_fuel = @fuel.sum { _2.to_f }.round(1)

  def average_flight = count.zero? ? nil : (total_flight / count).round(1)
  def longest_flight = @flights.map { flight_hours(_1) }.max&.round(1)

  # Gallons per tach hour over all fuel records.
  def gph = ConsumptionStats.new(@aircraft, "fuel").lifetime

  def airports
    @airports ||= @flights.flat_map { [ _1.departure_location, _1.destination_location ] }
                          .filter_map { _1.to_s.strip.upcase.presence }
  end

  def airports_visited = airports.uniq.size

  # Most-used airports (departures + arrivals), e.g. [["KOQU", 412], ...]
  def top_airports(limit = 5) = airports.tally.sort_by { [ -_2, _1 ] }.first(limit)

  def periods
    [
      period(I18n.t("services.flight_stats.past_30_days"), today - 29..today),
      period(I18n.t("services.flight_stats.past_12_months"), (today << 12) + 1..today),
      period(I18n.t("services.flight_stats.this_year", year: today.year), Date.new(today.year)..today),
      period(I18n.t("services.flight_stats.last_year", year: (today.year - 1)), Date.new(today.year - 1)..Date.new(today.year - 1, 12, 31)),
      period(I18n.t("services.flight_stats.since_purchase"), (first_date || today)..today)
    ]
  end

  def monthly_average_past_year
    (period("", (today << 12) + 1..today).flight / 12.0).round(1)
  end

  # { "Nov 2024" => 12.3, ... } for the last `months` months, including empty ones.
  def flight_hours_by_month(months = 24)
    start = (today << (months - 1)).beginning_of_month
    totals = @flights.select { _1.date >= start }.group_by { _1.date.beginning_of_month }
                     .transform_values { |fs| sum(fs) { flight_hours(_1) } }
    (0...months).to_h do |i|
      month = start >> i
      [ I18n.l(month, format: :month_year), totals.fetch(month, 0.0) ]
    end
  end

  def by_year
    years = (@flights.map { _1.date.year } + @fuel.map { _1[0].year }).uniq.sort.reverse
    years.map { |y| period(y.to_s, Date.new(y)..Date.new(y, 12, 31)) }
  end

  private

  def flight_hours(f) = (f.hobbs_time || f.tach_time).to_f

  def sum(items, &block) = items.sum { block.(_1).to_f }.round(1)

  def period(label, range)
    flights = @flights.select { range.cover?(_1.date) }
    Period.new(label: label, flights: flights.size,
               tach: sum(flights) { _1.tach_time }, flight: sum(flights) { flight_hours(_1) },
               fuel: @fuel.select { range.cover?(_1[0]) }.sum { _2.to_f }.round(1))
  end
end

# Oil/fuel consumption as a rolling rate: total added ÷ tach hours flown over a
# trailing window. Unlike per-fill math (qty added ÷ hours since the last add),
# this tolerates partial fills and top-offs: a 15 gal top-off 0.2 h after a
# partial fill no longer reads as 75 gal/hr.
#
#   oil  → hours per quart (higher is better)
#   fuel → gallons per hour
#
# Records marked "exclude from averages" (e.g. oil changes) still mark a point
# in time, but their quantity isn't counted.
class ConsumptionStats
  CHART_WINDOW_HOURS = { "oil" => 25, "fuel" => 10 }.freeze
  RECENT_WINDOW_HOURS = { "oil" => 100, "fuel" => 50 }.freeze

  attr_reader :record_type, :records

  def initialize(aircraft, record_type)
    @record_type = record_type
    @records = aircraft.consumable_records.where(record_type: record_type).order(:flight_hours, :date, :id).to_a
    @hours = @records.map { _1.flight_hours.to_f }
    # @prefix[i] = counted quantity of records[0...i]
    @prefix = @records.each_with_object([ 0.0 ]) do |r, acc|
      acc << acc.last + (r.excluded_from_averages? ? 0.0 : r.quantity_added.to_f)
    end
  end

  def oil? = record_type == "oil"
  def metric_label = oil? ? "hrs/qt" : "gal/hr"
  def chart_window_hours = CHART_WINDOW_HOURS.fetch(record_type)
  def recent_window_hours = RECENT_WINDOW_HOURS.fetch(record_type)

  # [[tach_hours, rate]] — the rolling rate at each record.
  def points
    @points ||= @records.each_index.filter_map do |i|
      rate = rate_ending_at(i, chart_window_hours)
      [ @hours[i].round(1), rate.round(2) ] if rate
    end
  end
  alias_method :chart_data, :points

  # Rate over roughly the last RECENT_WINDOW_HOURS (or all history if shorter).
  def recent
    return nil if @records.size < 2
    rate_ending_at(@records.size - 1, recent_window_hours, allow_shorter: true)&.round(1)
  end
  alias_method :average, :recent

  def lifetime
    return nil if @records.size < 2
    rate_between(0, @records.size - 1)&.round(1)
  end

  def latest = points.last&.last&.round(1)

  private

  # Rate over the shortest span ending at record i that covers >= window hours,
  # measured from an earlier record so it starts at a known fill point.
  def rate_ending_at(i, window, allow_shorter: false)
    target = @hours[i] - window
    j = (@hours.bsearch_index { _1 > target } || @hours.size) - 1 # last record at or before target
    j = 0 if j.negative? && allow_shorter
    return nil if j.negative? || j >= i
    rate_between(j, i)
  end

  # Quantity added after record j up to and including i, over the hours between them.
  def rate_between(j, i)
    span = @hours[i] - @hours[j]
    qty = @prefix[i + 1] - @prefix[j + 1]
    return nil unless span.positive? && qty.positive?
    oil? ? span / qty : qty / span
  end
end

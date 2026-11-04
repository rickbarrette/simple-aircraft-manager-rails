# Oil/fuel consumption: per-interval datapoints between consecutive records
# (sorted by flight hours), averaged over the last 20 with IQR outliers and
# excluded records left out. Oil → hours per quart; fuel → gallons per hour.
class ConsumptionStats
  WINDOW = 20
  Point = Struct.new(:record, :hours, :value, :excluded, :outlier, keyword_init: true)

  attr_reader :record_type, :records

  def initialize(aircraft, record_type)
    @record_type = record_type
    @records = aircraft.consumable_records.where(record_type: record_type).order(:flight_hours, :date).to_a
  end

  def oil? = record_type == "oil"
  def metric_label = oil? ? "hrs/qt" : "gal/hr"

  def points
    @points ||= begin
      pts = @records.each_cons(2).filter_map do |prev, cur|
        dh = (cur.flight_hours - prev.flight_hours).to_f
        qty = cur.quantity_added.to_f
        next unless qty > 0 && dh > 0
        Point.new(record: cur, hours: cur.flight_hours.to_f, value: oil? ? dh / qty : qty / dh,
                  excluded: cur.excluded_from_averages?)
      end
      bounds = iqr_bounds(pts.map(&:value))
      pts.each { |p| p.outlier = bounds && !(bounds[0]..bounds[1]).cover?(p.value) }
    end
  end

  def average
    window = points.last(WINDOW)
    return nil if window.empty?
    included = window.reject { |p| p.excluded || p.outlier }
    source = included.presence || window
    (source.sum(&:value) / source.size).round(1)
  end

  def latest = points.last&.value&.round(1)

  def chart_data
    points.map { |p| [ p.hours.round(1), p.value.round(2) ] }
  end

  private

  def iqr_bounds(values)
    return nil if values.size < 5
    nums = values.sort
    n = nums.size
    q1 = nums[n / 4]
    q3 = nums[(3 * n) / 4]
    iqr = q3 - q1
    return nil if iqr.zero?
    [ q1 - 1.5 * iqr, q3 + 1.5 * iqr ]
  end
end

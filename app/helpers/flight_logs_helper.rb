module FlightLogsHelper
  # Cylinder colors, mid-tone so they read on light and dark backgrounds.
  CYLINDER_COLORS = %w[#0ea5e9 #f97316 #22c55e #a855f7 #eab308 #ec4899].freeze

  # 519 → "8m 39s", 4000 → "1h 06m"
  def run_duration(seconds)
    s = seconds.to_i
    s >= 3600 ? format("%dh %02dm", s / 3600, s % 3600 / 60) : format("%dm %02ds", s / 60, s % 60)
  end

  def engine_value(value, unit, precision: 0)
    return "—" if value.nil?
    "#{number_with_delimiter(number_with_precision(value, precision: precision))} #{unit}"
  end

  def engine_chart(recording, *keys, ytitle:, colors: nil)
    series = recording.chart(*keys)
    return if series.empty?
    line_chart series, ytitle: ytitle, height: "200px", points: false, curve: false, colors: colors,
               legend: series.size > 1 ? "bottom" : false, library: { animation: false }
  end
end

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

  CHART_COLOR = "#3366CC".freeze # Chartkick's first color, for single-series charts

  # The charts shown for a recording; shared by the page and the interactive viewer.
  def engine_chart_groups(recording)
    [
      [ "CHT", recording.cht_keys, "°F", CYLINDER_COLORS ],
      [ "EGT", recording.egt_keys, "°F", CYLINDER_COLORS ],
      [ "RPM", [ :rpm ], "rpm" ],
      [ I18n.t("helpers.flight_logs.manifold_pressure"), [ :map ], "inHg" ],
      [ I18n.t("helpers.flight_logs.fuel_flow"), [ :fuel_flow ], "gph" ],
      [ I18n.t("helpers.flight_logs.oil_temp"), [ :oil_t ], "°F" ],
      [ I18n.t("helpers.flight_logs.oil_pressure"), [ :oil_p ], "psi" ],
      [ I18n.t("helpers.flight_logs.volts"), [ :volts ], "V" ]
    ].filter_map do |title, keys, unit, colors|
      keys = keys.select { recording.channels.key?(_1) }
      { title: title, keys: keys, unit: unit, colors: colors || [ CHART_COLOR ] } if keys.any?
    end
  end

  def engine_chart(recording, *keys, ytitle:, colors: nil)
    series = recording.chart(*keys)
    return if series.empty?
    line_chart series, ytitle: ytitle, height: "200px", points: false, curve: false, colors: colors,
               legend: series.size > 1 ? "bottom" : false, library: { animation: false }
  end
end

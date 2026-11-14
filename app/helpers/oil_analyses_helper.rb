module OilAnalysesHelper
  STATUS_BADGES = { "normal" => "badge-green", "monitor" => "badge-orange", "action_required" => "badge-red" }.freeze
  TREND_COLORS = %w[#0ea5e9 #f97316 #22c55e #a855f7 #eab308 #ec4899 #64748b].freeze

  # The lab's verdict; Blackstone reports don't rate samples, so there may be none.
  def oil_status_badge(analysis)
    return tag.span("Not rated", class: "badge-gray") unless analysis.status
    tag.span analysis.status_label, class: STATUS_BADGES[analysis.status]
  end

  def oil_property(analysis, key)
    value = analysis.property(key) or return "—"
    unit = OilAnalysis::PROPERTY_UNITS.fetch(key)
    number = number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
    unit.present? ? "#{number} #{unit}" : number
  end

  def ppm(value)
    value.nil? ? "—" : number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  # One cell: reading, lab average beneath, highlighted when well above the average.
  def ppm_cell(analysis, element)
    value = analysis.value(element)
    flagged = analysis.flagged?(element)
    content = tag.span(ppm(value), class: [ "tabular-nums", ("font-semibold text-red-700" if flagged) ],
                                   title: (I18n.t("helpers.oil_analyses.over_the_lab_average", _: (OilAnalysis::FLAG_RATIO)) if flagged))
    avg = analysis.average(element)
    avg ? safe_join([ content, tag.div("(#{ppm(avg)})", class: "text-xs text-slate-500 tabular-nums") ]) : content
  end

  # Change in ppm from the previous sample ("+3.2"), blank without one.
  def ppm_change(analysis, previous, element)
    return "" unless previous && (now = analysis.value(element)) && (before = previous.value(element))
    delta = now - before
    sign = delta.positive? ? "+" : ""
    "#{sign}#{ppm(delta)}"
  end

  # Samples marked "exclude from averages" (e.g. right after an overhaul) are left out.
  def oil_trend_series(analyses)
    chronological = analyses.reject(&:excluded_from_averages?).sort_by(&:sample_date)
    OilAnalysis::TREND_ELEMENTS.filter_map do |el|
      data = chronological.filter_map { |a| [ a.sample_date, a.value(el).to_f ] if a.value(el) }
      { name: OilAnalysis.element_label(el), data: data } if data.size >= 2
    end
  end
end

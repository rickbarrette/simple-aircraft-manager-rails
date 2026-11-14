module ApplicationHelper
  def hours(value)
    return "—" if value.nil?
    number_with_precision(value, precision: 1, delimiter: ",")
  end

  # How dates and times read across the app: "Nov 8, 2026", "Nov 8, 2026 14:05".
  # (Signatures and the record history keep exact UTC timestamps, 2026-11-08 14:05 UTC.)
  def fmt_date(value)
    value ? value.to_date.strftime("%b %-d, %Y") : "—"
  end

  def fmt_time(value)
    value ? value.in_time_zone.strftime("%b %-d, %Y %H:%M") : "—"
  end

  # Secondary actions (imports, exports, printing, tools) behind one "More"
  # button, so each section shows only its main action. The block gives the
  # items: links or button_to forms with class "menu-item".
  def more_menu(label = "More", small: false, &block)
    tag.details(class: "relative", data: { controller: "dropdown", action: "click@window->dropdown#closeOutside keydown.esc@window->dropdown#close" }) do
      tag.summary(class: [ "btn-secondary list-none [&::-webkit-details-marker]:hidden", ("btn-sm" if small) ], title: "More actions") do
        safe_join([ label, tag.span("▾", class: "text-xs", "aria-hidden": true) ], " ")
      end + tag.div(capture(&block), class: "menu")
    end
  end

  AIRWORTHINESS_COLORS = { "RED" => "red", "LIMITED" => "blue", "ORANGE" => "orange", "GREEN" => "green", "INFO" => "gray" }.freeze

  def airworthiness_badge(status, large: false)
    tag.span(status.label, class: [ "badge-#{AIRWORTHINESS_COLORS[status.status]}", ("text-sm px-3 py-1" if large) ],
                           title: Airworthiness::DISCLAIMER)
  end

  # Badge class (or text class) for one airworthiness issue.
  def issue_badge_class(issue) = "badge-#{AIRWORTHINESS_COLORS[issue.severity]}"

  def issue_text_class(issue)
    { "RED" => "text-red-700", "LIMITED" => "text-sky-700", "INFO" => "text-slate-600" }.fetch(issue.severity, "text-amber-700")
  end

  COMPLIANCE_BADGES = {
    "compliant" => [ "green", "Compliant" ], "due_soon" => [ "orange", "Due Soon" ],
    "overdue" => [ "red", "Overdue" ], "no_compliance" => [ "red", "No Record" ],
    "never_completed" => [ "red", "Never Completed" ], "conditional" => [ "gray", "Conditional" ],
    "not_applicable" => [ "gray", "N/A" ]
  }.freeze

  def compliance_badge(status)
    color, text = COMPLIANCE_BADGES.fetch(status, [ "gray", status.to_s.humanize ])
    tag.span(text, class: "badge-#{color}")
  end

  def life_badge(status)
    return "" unless status
    color, text = { overdue: [ "red", "Overdue" ], due_soon: [ "orange", "Due Soon" ], ok: [ "green", "OK" ] }[status]
    tag.span(text, class: "badge-#{color}")
  end

  def squawk_priority_badge(squawk)
    tag.span(squawk.priority_label, class: "badge-#{squawk.priority_color}")
  end

  def aircraft_status_badge(aircraft)
    color = { "AVAILABLE" => "green", "MX" => "orange", "GROUND" => "red", "UNAVAILABLE" => "gray" }[aircraft.status]
    tag.span(aircraft.status_label, class: "badge-#{color}")
  end

  def visibility_badge(visibility)
    color = { "private" => "gray", "status" => "green", "maintenance" => "blue" }[visibility]
    tag.span(DocumentCollection::VISIBILITIES[visibility], class: "badge-#{color}")
  end

  # AD number, linked to its document (opens in a new tab) when we have a link.
  def ad_link(ad)
    link = ad.reference_link
    return ad.name unless link
    link_to ad.name, link[0], class: "link", target: "_blank", rel: "noopener noreferrer", title: link[1]
  end

  def delete_button(label, path, confirm: "Are you sure?", **opts)
    button_to label, path, method: :delete, form: { data: { turbo_confirm: confirm }, class: "inline" },
              class: opts[:class] || "btn-danger btn-sm"
  end

  def empty_state(text)
    tag.p(text, class: "py-6 text-center text-sm text-slate-500")
  end

  def nav_tab(label, path, active)
    link_to label, path, class: [ "tab", ("tab-active" if active) ]
  end
end

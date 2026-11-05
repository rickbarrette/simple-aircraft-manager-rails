module ApplicationHelper
  def hours(value)
    return "—" if value.nil?
    number_with_precision(value, precision: 1, delimiter: ",")
  end

  def fmt_date(value)
    value ? l(value.to_date, format: :long) : "—"
  end

  def airworthiness_badge(status, large: false)
    color = { "RED" => "red", "ORANGE" => "orange", "GREEN" => "green" }[status.status]
    tag.span(status.label, class: [ "badge-#{color}", ("text-sm px-3 py-1" if large) ])
  end

  def airworthiness_dot(status)
    color = { "RED" => "bg-red-500", "ORANGE" => "bg-amber-400", "GREEN" => "bg-emerald-500" }[status.status]
    tag.span(class: "inline-block h-3 w-3 rounded-full #{color}", title: status.label)
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

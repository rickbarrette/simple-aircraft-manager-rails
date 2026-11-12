# Everything coming due on an aircraft, with a date: inspections, ADs,
# component replacement / TBO / inspection / expiry, and expiring documents.
# Items due by hours get a projected date from the aircraft's flying over
# the past year. Used by the calendar feed.
class DueList
  # past_hours: the hours have already run out (the date is then today).
  Item = Data.define(:key, :title, :date, :projected, :due_hours, :kind, :path, :past_hours) do
    def overdue?(today = Date.current) = past_hours || date < today
  end

  # Hours flown per day over the past year (nil when it hasn't flown).
  # What counts as coming up soon (Overview).
  SOON_DAYS = 30
  SOON_HOURS = 10

  def self.daily_rate(aircraft, today: Date.current)
    hours = aircraft.flight_logs.where(date: (today - 365)..today).sum(:tach_time).to_f
    hours.positive? ? hours / 365.0 : nil
  end

  def initialize(aircraft, today: Date.current)
    @aircraft = aircraft
    @today = today
    @rate = self.class.daily_rate(aircraft, today: today)
    @now_hours = aircraft.current_hours.to_d
    @urls = Rails.application.routes.url_helpers
  end

  def items
    (inspections + ads + components + documents).compact.sort_by { [ _1.date, _1.title ] }
  end

  # Due in the next SOON_DAYS days or SOON_HOURS hours (or overdue).
  def soon
    horizon = @today + SOON_DAYS
    hours_limit = @now_hours + SOON_HOURS
    items.select { |i| i.date <= horizon || (i.due_hours && i.due_hours <= hours_limit) }
  end

  private

  # The date it's due: the calendar date, or when the hours run out at the
  # current rate, whichever comes first.
  def item(key, title, kind, path, date: nil, hours_left: nil)
    projected = hours_left && @rate ? @today + (hours_left.to_f / @rate).floor : nil
    projected = @today if projected && projected < @today
    use = [ date, projected ].compact.min
    return unless use
    Item.new(key: key, title: title, date: use, projected: use == projected && projected != date, kind: kind, path: path,
             due_hours: hours_left ? (@now_hours + hours_left.to_d).round(1) : nil,
             past_hours: !hours_left.nil? && hours_left.negative? && use == projected)
  end

  def hours_left(due_hours) = due_hours ? due_hours.to_d - @now_hours : nil

  def inspections
    Compliance.inspection_rows(@aircraft).map do |r|
      item("inspection-#{r.type.id}", "#{r.type.name} due", "inspection", @urls.aircraft_inspections_path(@aircraft),
           date: r.next_due_date, hours_left: hours_left(r.next_due_hours))
    end
  end

  def ads
    Compliance.ad_rows(@aircraft).map do |r|
      next if r.status.to_s.in?(%w[not_applicable na conditional])
      item("ad-#{r.ad.id}", "AD #{r.ad.name} due", "ad", @urls.aircraft_airworthiness_directives_path(@aircraft),
           date: r.next_due_date, hours_left: hours_left(r.next_due_hours))
    end
  end

  # A component's own "Inspect every" counts from its last service; when an
  # inspection type covers the component, that inspection (tracked from its
  # records, under inspections) governs instead.
  def components
    @aircraft.components.in_use.includes(:component_type, :inspection_types).flat_map do |c|
      label = "#{c} #{c.model}".strip
      path = @urls.aircraft_component_path(@aircraft, c)
      since_service = c.hours_since_overhaul.to_d
      [
        (item("replace-#{c.id}", "Replace #{label}", "component", path, date: c.next_replacement_date,
              hours_left: c.replacement_hours && c.replacement_hours - since_service) if c.replacement_hours || c.replacement_calendar?),
        (item("tbo-#{c.id}", "#{label} reaches TBO", "component", path,
              date: c.tbo_after(c.overhaul_date),
              hours_left: c.tbo_hours && c.tbo_hours - since_service) if (c.tbo_hours || c.tbo_calendar?) && !c.on_condition?),
        (item("inspect-#{c.id}", "Inspect #{label}", "component", path,
              date: c.inspection_after(c.overhaul_date),
              hours_left: c.inspection_hours && c.inspection_hours - since_service) if (c.inspection_hours || c.inspection_calendar?) && c.inspection_types.empty?),
        (item("expires-#{c.id}", "#{label} expires", "component", path, date: c.expires_on) if c.expires_on)
      ]
    end
  end

  def documents
    @aircraft.documents.expiring.map do |d|
      item("document-#{d.id}", "#{d.name} expires", "document", @urls.aircraft_document_path(@aircraft, d), date: d.expires_on)
    end
  end
end

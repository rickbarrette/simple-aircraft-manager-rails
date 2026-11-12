# Everything coming due on an aircraft, with a date: inspections, ADs,
# component replacement / TBO / inspection / expiry, and expiring documents.
# Items due by hours get a projected date from the aircraft's flying over
# the past year. Used by the calendar feed.
class DueList
  Item = Data.define(:key, :title, :date, :projected, :due_hours, :kind, :path) do
    def overdue?(today = Date.current) = date < today
  end

  # Hours flown per day over the past year (nil when it hasn't flown).
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

  private

  # The date it's due: the calendar date, or when the hours run out at the
  # current rate, whichever comes first.
  def item(key, title, kind, path, date: nil, hours_left: nil)
    projected = hours_left && @rate ? @today + (hours_left.to_f / @rate).floor : nil
    projected = @today if projected && projected < @today
    use = [ date, projected ].compact.min
    return unless use
    Item.new(key: key, title: title, date: use, projected: use == projected && projected != date, kind: kind, path: path,
             due_hours: hours_left ? (@now_hours + hours_left.to_d).round(1) : nil)
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

  def components
    @aircraft.components.in_use.includes(:component_type).flat_map do |c|
      label = "#{c} #{c.model}".strip
      path = @urls.aircraft_component_path(@aircraft, c)
      since_service = c.hours_since_overhaul.to_d
      [
        (item("replace-#{c.id}", "Replace #{label}", "component", path, date: c.next_replacement_date,
              hours_left: c.replacement_hours && c.replacement_hours - since_service) if c.replacement_hours || c.replacement_days),
        (item("tbo-#{c.id}", "#{label} reaches TBO", "component", path,
              date: c.tbo_days && c.overhaul_date ? c.overhaul_date + c.tbo_days : nil,
              hours_left: c.tbo_hours && c.tbo_hours - since_service) if (c.tbo_hours || c.tbo_days) && !c.on_condition?),
        (item("inspect-#{c.id}", "Inspect #{label}", "component", path,
              date: c.inspection_days && c.overhaul_date ? c.overhaul_date + c.inspection_days : nil,
              hours_left: c.inspection_hours && c.inspection_hours - since_service) if c.inspection_hours || c.inspection_days),
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

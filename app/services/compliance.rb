# Shared AD / inspection due-status math (port of ad_compliance_status /
# inspection_compliance_status from the original health/services.py).
module Compliance
  COMPLIANT = 0
  DUE_SOON = 1
  OVERDUE = 2
  LABELS = %w[compliant due_soon overdue].freeze

  Result = Struct.new(:rank, :next_due_date, :next_due_hours, keyword_init: true) do
    def label = LABELS[rank]
  end

  module_function

  # Last day of the month `months` after `date` (FAA "end of month" convention).
  def end_of_month_after(date, months)
    (date >> months).end_of_month
  end

  # Next due date/hours from a recurrence rule ({hours:, months:, days:}),
  # matching the status math below: months land on the end of the month,
  # then days are added; hours are added to the hours at completion.
  def next_due(rule, date:, hours:)
    return {} unless rule
    due = {}
    if rule[:months].to_i.positive? || rule[:days].to_i.positive?
      d = date
      d = end_of_month_after(d, rule[:months].to_i) if rule[:months].to_i.positive?
      d += rule[:days].to_i.days if rule[:days].to_i.positive?
      due[:date] = d if date
    end
    due[:hours] = hours.to_d + rule[:hours].to_d if rule[:hours].to_d.positive? && hours
    due
  end

  def ad_status(ad, compliance, current_hours, today = Date.current)
    return Result.new(rank: COMPLIANT) if ad.conditional?
    return Result.new(rank: OVERDUE) unless compliance
    return Result.new(rank: COMPLIANT) if compliance.closed?

    rank = COMPLIANT
    result = Result.new

    due_hours = compliance.next_due_at_time.to_d
    if due_hours > 0
      result.next_due_hours = due_hours
      if current_hours >= due_hours
        rank = OVERDUE
      elsif current_hours + Airworthiness::HOURS_WARNING >= due_hours
        rank = [ rank, DUE_SOON ].max
      end
    end

    if ad.recurring? && ad.recurring_months.positive?
      due = end_of_month_after(compliance.date_complied, ad.recurring_months)
      result.next_due_date = due
      if today > due
        rank = OVERDUE
      elsif today + Airworthiness::DAYS_WARNING >= due
        rank = [ rank, DUE_SOON ].max
      end
    end

    result.rank = rank
    result
  end

  # `records` are those that count for the type (InspectionType#records_for).
  # Calendar intervals run from the latest one's date. Hour intervals run from
  # the hours at the latest one, except that an inspection done late, within
  # the type's hours_tolerance, is counted from when it was due (91.409(b):
  # the 100-hour's 10-hour allowance counts toward the next 100 hours). Done
  # early, there's no credit: the next is counted from when it was done.
  def inspection_status(type, records, current_hours, today = Date.current)
    records = records.to_a
    last_record = records.max_by { [ _1.date, _1.created_at || Time.at(0) ] }
    return Result.new(rank: OVERDUE) unless last_record
    return Result.new(rank: COMPLIANT) unless type.recurring?

    rank = COMPLIANT
    result = Result.new

    if type.recurring_months.positive? || type.recurring_days.positive?
      due = last_record.date
      due = end_of_month_after(due, type.recurring_months) if type.recurring_months.positive?
      due += type.recurring_days.days if type.recurring_days.positive?
      result.next_due_date = due
      if today > due
        rank = OVERDUE
      elsif today + Airworthiness::DAYS_WARNING >= due
        rank = [ rank, DUE_SOON ].max
      end
    end

    if (due_hours = next_due_hours(type, records))
      result.next_due_hours = due_hours
      if current_hours >= due_hours
        rank = OVERDUE
      elsif current_hours + Airworthiness::HOURS_WARNING >= due_hours
        rank = [ rank, DUE_SOON ].max
      end
    end

    result.rank = rank
    result
  end

  def next_due_hours(type, records)
    interval = type.recurring_hours.to_d
    return unless interval.positive?
    tolerance = type.hours_tolerance.to_d
    due = nil
    records.select(&:hours_at_inspection).sort_by { [ _1.date, _1.hours_at_inspection ] }.each do |r|
      hours = r.hours_at_inspection.to_d
      base = due && hours > due && hours - due <= tolerance ? due : hours
      due = base + interval
    end
    due
  end

  # Rows for the ADs tab: every applicable AD with its latest compliance and status.
  AdRow = Struct.new(:ad, :latest, :status, :next_due_date, :next_due_hours, keyword_init: true)

  def ad_rows(aircraft)
    hours = aircraft.current_hours
    aircraft.applicable_ads.ordered.map do |ad|
      latest = ad.latest_compliance_for(aircraft)
      status =
        if ad.conditional? then latest ? "compliant" : "conditional"
        elsif latest.nil? then "no_compliance"
        elsif latest.not_applicable? then "not_applicable"
        elsif latest.permanent? then "compliant"
        end
      res = ad_status(ad, latest, hours) unless status
      AdRow.new(ad: ad, latest: latest, status: status || res.label,
                next_due_date: res&.next_due_date, next_due_hours: res&.next_due_hours)
    end
  end

  InspectionRow = Struct.new(:type, :latest, :status, :next_due_date, :next_due_hours, keyword_init: true)

  def inspection_rows(aircraft)
    hours = aircraft.current_hours
    aircraft.applicable_inspection_types.ordered.map do |type|
      records = type.records_for(aircraft).to_a
      latest = records.max_by { [ _1.date, _1.created_at || Time.at(0) ] }
      if latest.nil?
        InspectionRow.new(type: type, latest: nil, status: "never_completed")
      else
        res = inspection_status(type, records, hours)
        InspectionRow.new(type: type, latest: latest, status: res.label,
                          next_due_date: res.next_due_date, next_due_hours: res.next_due_hours)
      end
    end
  end
end

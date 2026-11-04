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

  def ad_status(ad, compliance, current_hours, today = Date.current)
    return Result.new(rank: COMPLIANT) if ad.conditional?
    return Result.new(rank: OVERDUE) unless compliance
    return Result.new(rank: COMPLIANT) if compliance.permanent?

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

  def inspection_status(type, last_record, current_hours, today = Date.current)
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

    interval = type.recurring_hours.to_d
    if interval > 0 && (hours_at = last_record.hours_at_inspection)
      since = current_hours - hours_at
      result.next_due_hours = hours_at + interval
      if since >= interval
        rank = OVERDUE
      elsif since + Airworthiness::HOURS_WARNING >= interval
        rank = [ rank, DUE_SOON ].max
      end
    end

    result.rank = rank
    result
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
      latest = type.inspection_records.for_aircraft(aircraft).recent_first.first
      if latest.nil?
        InspectionRow.new(type: type, latest: nil, status: "never_completed")
      else
        res = inspection_status(type, latest, hours)
        InspectionRow.new(type: type, latest: latest, status: res.label,
                          next_due_date: res.next_due_date, next_due_hours: res.next_due_hours)
      end
    end
  end
end

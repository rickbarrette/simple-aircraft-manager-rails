# Computes RED / ORANGE / GREEN airworthiness for an aircraft. Checks (in order):
# AD compliance, grounding squawks, inspection recurrency, component replacement.
class Airworthiness
  HOURS_WARNING = BigDecimal("10")
  DAYS_WARNING = 30

  RED = "RED"
  ORANGE = "ORANGE"
  GREEN = "GREEN"

  Issue = Struct.new(:category, :severity, :title, :description, :item, keyword_init: true)

  Status = Struct.new(:status, :issues, keyword_init: true) do
    def red? = status == RED
    def orange? = status == ORANGE
    def green? = status == GREEN
    def can_fly? = green?
    def red_issues = issues.select { |i| i.severity == RED }
    def label = { RED => "Not Airworthy", ORANGE => "Attention Needed", GREEN => "Airworthy" }[status]
  end

  def initialize(aircraft, today: Date.current)
    @aircraft = aircraft
    @today = today
    @hours = aircraft.current_hours
    @issues = []
  end

  def call
    check_ads
    check_grounding_squawks
    check_inspections
    check_components

    status =
      if @issues.any? { _1.severity == RED } then RED
      elsif @issues.any? { _1.severity == ORANGE } then ORANGE
      else GREEN
      end
    Status.new(status: status, issues: @issues)
  end

  private

  def add(category, severity, title, description, item)
    @issues << Issue.new(category:, severity:, title:, description:, item:)
  end

  def check_ads
    @aircraft.applicable_ads.where(mandatory: true, compliance_type: "standard").find_each do |ad|
      compliance = ad.latest_compliance_for(@aircraft)
      res = Compliance.ad_status(ad, compliance, @hours, @today)
      label = ad.bulletin_label
      case res.rank
      when Compliance::OVERDUE
        desc = compliance ? "#{ad.short_description}. Compliance overdue." : "#{ad.short_description}. No compliance record found."
        add("AD", RED, "#{label} #{ad.name} - Overdue", desc, ad)
      when Compliance::DUE_SOON
        add("AD", ORANGE, "#{label} #{ad.name} - Due Soon", "#{ad.short_description}. Compliance due soon.", ad)
      end
    end
  end

  def check_grounding_squawks
    @aircraft.squawks.active.where(priority: 0).find_each do |squawk|
      add("SQUAWK", RED, "Grounding Squawk", squawk.issue_reported.to_s.truncate(100).presence || "No description", squawk)
    end
  end

  def check_inspections
    @aircraft.applicable_inspection_types.where(required: true).find_each do |type|
      last = type.inspection_records.for_aircraft(@aircraft).recent_first.first
      res = Compliance.inspection_status(type, last, @hours, @today)
      case res.rank
      when Compliance::OVERDUE
        if last
          add("INSPECTION", RED, "#{type.name} - Overdue", "Inspection overdue.", type)
        else
          add("INSPECTION", RED, "#{type.name} - Never Completed", "Required inspection has no completion record.", type)
        end
      when Compliance::DUE_SOON
        add("INSPECTION", ORANGE, "#{type.name} - Due Soon", "Inspection due soon.", type)
      end
    end
  end

  def check_components
    @aircraft.components.in_use.where(replacement_critical: true).includes(:component_type).find_each do |c|
      overdue = false
      approaching = false
      desc = ""

      if c.replacement_hours
        if c.hours_since_overhaul >= c.replacement_hours
          overdue = true
          desc = "Replace every #{c.replacement_hours} hrs. Current: #{c.hours_since_overhaul} hrs."
        elsif c.hours_since_overhaul + HOURS_WARNING >= c.replacement_hours
          approaching = true
          desc = "Replace in #{c.replacement_hours - c.hours_since_overhaul} hrs."
        end
      end

      if (due = c.next_replacement_date)
        if @today >= due
          overdue = true
          desc = "Replace every #{c.replacement_days} days. Last serviced #{c.overhaul_date}."
        elsif @today + DAYS_WARNING >= due
          approaching = true
          desc = "Replace in #{(due - @today).to_i} days."
        end
      end

      if overdue
        add("COMPONENT", RED, "#{c} - Replacement Overdue", desc, c)
      elsif approaching
        add("COMPONENT", ORANGE, "#{c} - Replacement Due Soon", desc, c)
      end
    end
  end
end

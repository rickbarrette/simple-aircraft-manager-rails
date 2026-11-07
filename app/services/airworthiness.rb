# Summarizes an aircraft's records: AD compliance, grounding squawks,
# inspection recurrency and component replacement.
#
#   RED     something that grounds the aircraft is overdue
#   LIMITED it may fly with limitations (pitot-static overdue: VFR only;
#           transponder check overdue: no transponder)
#   ORANGE  something is due soon
#   GREEN   nothing overdue or due soon
#
# This reflects only what's recorded here. Before each flight the pilot in
# command decides whether the aircraft is airworthy (14 CFR 91.7).
class Airworthiness
  HOURS_WARNING = BigDecimal("10")
  DAYS_WARNING = 30

  RED = "RED"
  LIMITED = "LIMITED"
  INFO = "INFO" # listed for awareness; doesn't change the status (a deferred inoperative item)
  ORANGE = "ORANGE"
  GREEN = "GREEN"
  DISCLAIMER = "Based on the records in this app. Before each flight the pilot in command decides whether the aircraft is airworthy (14 CFR 91.7)."

  Issue = Struct.new(:category, :severity, :title, :description, :item, :limitation, keyword_init: true)

  Status = Struct.new(:status, :issues, keyword_init: true) do
    def red? = status == RED
    def limited? = status == LIMITED
    def orange? = status == ORANGE
    def green? = status == GREEN
    def can_fly? = !red?
    def red_issues = issues.select { |i| i.severity == RED }
    def limitations = issues.filter_map(&:limitation).uniq

    def label
      case status
      when RED then "Grounded"
      when LIMITED then limitations.join(" · ")
      when ORANGE then "Due soon"
      else "Current"
      end
    end
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
    check_documents

    status =
      if @issues.any? { _1.severity == RED } then RED
      elsif @issues.any? { _1.severity == LIMITED } then LIMITED
      elsif @issues.any? { _1.severity == ORANGE } then ORANGE
      else GREEN
      end
    Status.new(status: status, issues: @issues)
  end

  private

  def add(category, severity, title, description, item, limitation: nil)
    @issues << Issue.new(category:, severity:, title:, description:, item:, limitation:)
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
    @aircraft.squawks.active.where(priority: 0, deferred_at: nil).find_each do |squawk|
      add("SQUAWK", RED, "Grounding Squawk", squawk.issue_reported.to_s.truncate(100).presence || "No description", squawk)
    end
    @aircraft.squawks.deferred.find_each do |squawk|
      add("DEFERRED", INFO, "Inoperative: #{squawk.issue_reported.to_s.truncate(80)}",
          "Deferred under 91.213(d) on #{squawk.deferred_at.to_date} by #{squawk.deferred_by_name}. Fix at the next inspection.", squawk)
    end
  end

  def check_inspections
    @aircraft.applicable_inspection_types.where.not(effect: "advisory").includes(:satisfied_by).find_each do |type|
      records = type.records_for(@aircraft).to_a
      res = Compliance.inspection_status(type, records, @hours, @today)
      case res.rank
      when Compliance::OVERDUE
        title = "#{type.name} - #{records.any? ? 'Overdue' : 'Never Completed'}"
        if (limitation = type.limitation)
          add("INSPECTION", LIMITED, title, "#{limitation} until it's done.", type, limitation: limitation)
        else
          add("INSPECTION", RED, title, overdue_description(type, records, res), type)
        end
      when Compliance::DUE_SOON
        add("INSPECTION", ORANGE, "#{type.name} - Due Soon", "Inspection due soon.", type)
      end
    end
  end

  # The 100-hour may be overflown by up to its tolerance only to reach a
  # place where it can be done (91.409(b)); say so while that's still open.
  def overdue_description(type, records, res)
    return "Required inspection has no completion record." if records.empty?
    over = res.next_due_hours && @hours - res.next_due_hours
    if over && type.hours_tolerance.positive? && over <= type.hours_tolerance
      "Inspection overdue. It may be flown up to #{type.hours_tolerance.to_s.sub(/\.0\z/, '')} hrs past due only to reach " \
        "a place where it can be done; that time counts toward the next interval (91.409(b))."
    else
      "Inspection overdue."
    end
  end

  def check_documents
    @aircraft.documents.expiring.find_each do |doc|
      grounds = Document::GROUNDING_EXPIRY_TYPES.include?(doc.doc_type)
      if doc.expired?(@today)
        add("DOCUMENT", grounds ? RED : ORANGE, "#{doc.name} - Expired",
            "#{doc.type_label} expired #{doc.expires_on}.#{' The aircraft may not be flown without a current registration (91.203).' if grounds}", doc)
      elsif @today + doc.expiry_warning_days >= doc.expires_on
        add("DOCUMENT", ORANGE, "#{doc.name} - Expires Soon", "#{doc.type_label} expires #{doc.expires_on}.", doc)
      end
    end
  end

  def check_components
    scope = @aircraft.components.in_use.where(replacement_critical: true).or(@aircraft.components.in_use.where.not(expires_on: nil))
    scope.includes(:component_type).find_each do |c|
      overdue = false
      approaching = false
      desc = ""

      if c.replacement_critical? && c.replacement_hours
        if c.hours_since_overhaul >= c.replacement_hours
          overdue = true
          desc = "Replace every #{c.replacement_hours} hrs. Current: #{c.hours_since_overhaul} hrs."
        elsif c.hours_since_overhaul + HOURS_WARNING >= c.replacement_hours
          approaching = true
          desc = "Replace in #{c.replacement_hours - c.hours_since_overhaul} hrs."
        end
      end

      if c.replacement_critical? && (due = c.next_replacement_date)
        if @today >= due
          overdue = true
          desc = "Replace every #{c.replacement_days} days. Last serviced #{c.overhaul_date}."
        elsif @today + DAYS_WARNING >= due
          approaching = true
          desc = "Replace in #{(due - @today).to_i} days."
        end
      end

      expired = false
      if c.expires_on
        if c.expired?(@today)
          expired = true
          desc = "Expired #{c.expires_on}."
        elsif @today + DAYS_WARNING >= c.expires_on
          approaching = true
          desc = "Expires #{c.expires_on}."
        end
      end

      if overdue || (expired && c.replacement_critical?)
        add("COMPONENT", RED, "#{c} - #{expired ? 'Expired' : 'Replacement Overdue'}", desc, c)
      elsif expired
        add("COMPONENT", ORANGE, "#{c} - Expired", desc, c)
      elsif approaching
        add("COMPONENT", ORANGE, "#{c} - #{c.expires_on && desc.start_with?('Expires') ? 'Expires Soon' : 'Replacement Due Soon'}", desc, c)
      end
    end
  end
end

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
  def self.disclaimer = I18n.t("services.airworthiness.disclaimer")
  def self.t(key, **opts) = I18n.t(key, scope: "services.airworthiness", **opts)

  Issue = Struct.new(:category, :severity, :title, :description, :item, :limitation, keyword_init: true) do
    def category_label = Airworthiness.t(category, scope: "services.airworthiness.categories")
  end

  Status = Struct.new(:status, :issues, keyword_init: true) do
    def red? = status == RED
    def limited? = status == LIMITED
    def orange? = status == ORANGE
    def green? = status == GREEN
    def red_issues = issues.select { |i| i.severity == RED }
    def limitations = issues.filter_map(&:limitation).uniq

    def label
      case status
      when RED then Airworthiness.t(:grounded)
      when LIMITED then limitations.join(" · ")
      when ORANGE then Airworthiness.t(:due_soon)
      else Airworthiness.t(:current)
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

  def t(key, **opts) = self.class.t(key, **opts)

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
        desc = t(compliance ? :ad_overdue : :ad_no_record, description: ad.short_description)
        add("AD", RED, t(:ad_overdue_title, label: label, name: ad.name), desc, ad)
      when Compliance::DUE_SOON
        add("AD", ORANGE, t(:ad_due_soon_title, label: label, name: ad.name), t(:ad_due_soon, description: ad.short_description), ad)
      end
    end
  end

  def check_grounding_squawks
    @aircraft.squawks.active.where(priority: 0, deferred_at: nil).find_each do |squawk|
      add("SQUAWK", RED, t(:grounding_squawk), squawk.issue_reported.to_s.truncate(100).presence || t(:no_description), squawk)
    end
    @aircraft.squawks.deferred.find_each do |squawk|
      add("DEFERRED", INFO, t(:inoperative, issue: squawk.issue_reported.to_s.truncate(80)),
          t(:deferred, date: squawk.deferred_at.to_date, name: squawk.deferred_by_name), squawk)
    end
  end

  def check_inspections
    @aircraft.applicable_inspection_types.where.not(effect: "advisory").includes(:satisfied_by).find_each do |type|
      records = type.records_for(@aircraft).to_a
      res = Compliance.inspection_status(type, records, @hours, @today)
      case res.rank
      when Compliance::OVERDUE
        title = t(records.any? ? :inspection_overdue_title : :inspection_never_title, name: type.name)
        if (limitation = type.limitation)
          add("INSPECTION", LIMITED, title, t(:limited_until_done, limitation: limitation), type, limitation: limitation)
        else
          add("INSPECTION", RED, title, overdue_description(type, records, res), type)
        end
      when Compliance::DUE_SOON
        add("INSPECTION", ORANGE, t(:inspection_due_soon_title, name: type.name), t(:inspection_due_soon), type)
      end
    end
  end

  # The 100-hour may be overflown by up to its tolerance only to reach a
  # place where it can be done (91.409(b)); say so while that's still open.
  def overdue_description(type, records, res)
    return t(:no_completion_record) if records.empty?
    over = res.next_due_hours && @hours - res.next_due_hours
    if over && type.hours_tolerance.positive? && over <= type.hours_tolerance
      t(:inspection_overdue_tolerance, hours: type.hours_tolerance.to_s.sub(/\.0\z/, ""))
    else
      t(:inspection_overdue)
    end
  end

  def check_documents
    @aircraft.documents.expiring.find_each do |doc|
      grounds = Document::GROUNDING_EXPIRY_TYPES.include?(doc.doc_type)
      if doc.expired?(@today)
        add("DOCUMENT", grounds ? RED : ORANGE, t(:expired_title, name: doc.name),
            t(grounds ? :document_expired_grounds : :document_expired, type: doc.type_label, date: doc.expires_on), doc)
      elsif @today + doc.expiry_warning_days >= doc.expires_on
        add("DOCUMENT", ORANGE, t(:expires_soon_title, name: doc.name), t(:document_expires, type: doc.type_label, date: doc.expires_on), doc)
      end
    end
  end

  def check_components
    scope = @aircraft.components.in_use.where(replacement_critical: true).or(@aircraft.components.in_use.where.not(expires_on: nil))
    scope.includes(:component_type).find_each do |c|
      overdue = false
      approaching = false
      expiring = false
      desc = ""

      if c.replacement_critical? && c.replacement_hours
        used = c.replacement_hours_used
        if used >= c.replacement_hours
          overdue = true
          desc = t(c.replacement_from_install? ? :replace_every_hours_installed : :replace_every_hours, hours: c.replacement_hours, used: used)
        elsif used + HOURS_WARNING >= c.replacement_hours
          approaching = true
          desc = t(:replace_in_hours, hours: c.replacement_hours - used)
        end
      end

      if c.replacement_critical? && (due = c.next_replacement_date)
        if @today >= due
          overdue = true
          desc = t(c.replacement_from_install? ? :replace_every_installed : :replace_every_serviced, interval: c.replacement_interval_label, date: c.replacement_counted_from)
        elsif @today + DAYS_WARNING >= due
          approaching = true
          desc = t(:replace_in_days, count: (due - @today).to_i)
        end
      end

      expired = false
      if c.expires_on
        if c.expired?(@today)
          expired = true
          desc = t(:component_expired, date: c.expires_on)
        elsif @today + DAYS_WARNING >= c.expires_on
          approaching = true
          expiring = true
          desc = t(:component_expires, date: c.expires_on)
        end
      end

      if overdue || (expired && c.replacement_critical?)
        add("COMPONENT", RED, t(expired ? :expired_title : :replacement_overdue_title, name: c), desc, c)
      elsif expired
        add("COMPONENT", ORANGE, t(:expired_title, name: c), desc, c)
      elsif approaching
        add("COMPONENT", ORANGE, t(expiring ? :expires_soon_title : :replacement_due_soon_title, name: c), desc, c)
      end
    end
  end
end

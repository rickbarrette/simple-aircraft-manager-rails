class Component < ApplicationRecord
  include Versioned
  include CalendarInterval
  STATUSES = LabelSet.new("component.statuses", %w[SPARE IN-USE DISPOSED])
  # What "since overhaul" counts from, and how logbooks abbreviate it.
  OVERHAUL_KINDS = LabelSet.new("component.overhaul_kinds", %w[major factory_overhaul factory_new])
  OVERHAUL_ABBREVIATIONS = { "major" => "SMOH", "factory_overhaul" => "SFOH", "factory_new" => "SNEW" }.freeze

  calendar_interval :replacement, days: :replacement_days, months: :replacement_months
  calendar_interval :tbo, days: :tbo_days, months: :tbo_months

  belongs_to :aircraft, optional: true
  belongs_to :parent_component, class_name: "Component", optional: true
  belongs_to :component_type
  has_many :child_components, class_name: "Component", foreign_key: :parent_component_id, dependent: :destroy
  has_many :squawks, dependent: :nullify
  has_many :oil_analyses, dependent: :nullify
  # Records about this component outlive it (their foreign keys would otherwise block deleting it).
  has_many :ad_compliances, dependent: :nullify
  has_many :inspection_records, dependent: :nullify
  has_many :major_records, dependent: :nullify
  has_many :logbook_entries, dependent: :nullify
  has_many :logbook_entry_parts, dependent: :destroy
  has_and_belongs_to_many :inspection_types
  has_and_belongs_to_many :airworthiness_directives
  # Its AD and inspection links go with it; keep that in the record history.
  before_destroy(prepend: true) { (airworthiness_directives.to_a + inspection_types.to_a).each { _1.history_component_deleted(self) } }

  validates :manufacturer, :model, :date_in_service, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :overhaul_kind, inclusion: { in: OVERHAUL_KINDS.keys }, allow_blank: true
  validate :parent_on_same_aircraft

  scope :in_use, -> { where(status: "IN-USE") }

  def to_s
    [ component_type&.name, install_location.presence && "(#{install_location})" ].compact.join(" ")
  end

  def status_label = STATUSES[status]
  # SMOH / SFOH / SNEW when the overhaul type is known; engines and
  # propellers otherwise "TSO", and other parts (filters…) "since service".
  def since_overhaul_abbreviation
    OVERHAUL_ABBREVIATIONS.fetch(overhaul_kind) { engine? || propeller? ? "TSO" : I18n.t("models.component.since_service") }
  end

  # Its sub-components, and theirs. (Stops at a loop, should one exist.)
  def descendant_ids(seen = Set[id])
    child_components.flat_map do |child|
      next [] unless seen.add?(child.id)
      [ child.id, *child.descendant_ids(seen) ]
    end
  end

  # Its parent, the parent's parent, and so on up.
  def ancestor_ids
    ids = []
    node = self
    while (parent_id = node.parent_component_id) && parent_id != id && !ids.include?(parent_id)
      ids << parent_id
      node = Component.find_by(id: parent_id) or break
    end
    ids
  end
  def engine? = component_type&.name.to_s.match?(/engine/i)
  def propeller? = component_type&.name.to_s.match?(/propell?er|\bprop\b/i)

  # "On condition" means TBO isn't a limit, so it's never also a hard limit.
  before_validation { self.tbo_critical = false if on_condition? }

  def hours_to_tbo
    tbo_hours - hours_since_overhaul if tbo_hours
  end

  # The hours the replacement limit counts: since installed for a life-limited
  # part that's serviced and reused, else since its last service.
  def replacement_hours_used = replacement_from_install? ? hours_in_service : hours_since_overhaul

  def replacement_counted_from = replacement_from_install? ? date_in_service : overhaul_date

  def hours_to_replacement
    replacement_hours - replacement_hours_used if replacement_hours
  end

  # Past the date marked on the part (it may be used through that date).
  def expired?(today = Date.current) = expires_on.present? && today > expires_on

  def next_replacement_date
    replacement_after(replacement_counted_from)
  end

  # :overdue / :due_soon / :ok / nil (not tracked) for display on the components tab.
  def life_status
    statuses = []
    if replacement_critical?
      if replacement_hours
        statuses << rank(hours_to_replacement <= 0, hours_to_replacement <= Airworthiness::HOURS_WARNING)
      end
      if (d = next_replacement_date)
        statuses << rank(Date.current >= d, Date.current + Airworthiness::DAYS_WARNING >= d)
      end
    end
    statuses << rank(expired?, Date.current + Airworthiness::DAYS_WARNING >= expires_on) if expires_on
    if tbo_critical? && tbo_hours && !on_condition?
      statuses << rank(hours_to_tbo <= 0, hours_to_tbo <= Airworthiness::HOURS_WARNING * 5)
    end
    return nil if statuses.empty?
    %i[overdue due_soon ok].find { |s| statuses.include?(s) }
  end

  # Service reset: always zeroes time since overhaul; optionally the whole
  # in-service clock when the part was physically replaced.
  # Serviced (or replaced) as recorded in a logbook entry: dated to the entry,
  # with the hours it has run since then as the new time since service. That's
  # the airframe time flown since the entry when known (the part's own total
  # at the entry is often typed as 0 for new oil, which would keep the old
  # hours), else its total time now less its total time at the entry.
  def service_from_entry!(date:, hours_at_entry:, flown_since: nil, replaced: false)
    since =
      if flown_since then flown_since.to_d
      elsif hours_at_entry then hours_in_service.to_d - hours_at_entry.to_d
      else 0
      end
    since = [ since, 0 ].max
    since = [ since, hours_in_service.to_d ].min unless replaced # can't have run longer since service than in total
    attrs = { hours_since_overhaul: since, overhaul_date: date }
    attrs.merge!(hours_in_service: since, date_in_service: date) if replaced
    update!(attrs)
  end

  def reset_service!(reset_in_service: false)
    attrs = { hours_since_overhaul: 0, overhaul_date: Date.current }
    attrs.merge!(hours_in_service: 0, date_in_service: Date.current) if reset_in_service
    update!(attrs)
  end

  private

  def rank(overdue, soon)
    overdue ? :overdue : (soon ? :due_soon : :ok)
  end

  def parent_on_same_aircraft
    return unless parent_component
    errors.add(:parent_component, :itself) if parent_component_id == id && id
    errors.add(:parent_component, :own_part) if id && parent_component.ancestor_ids.include?(id) # would make a loop
    errors.add(:parent_component, :other_aircraft) if parent_component.aircraft_id != aircraft_id
  end
end

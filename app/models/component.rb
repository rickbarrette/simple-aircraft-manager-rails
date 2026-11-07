class Component < ApplicationRecord
  STATUSES = { "SPARE" => "Spare Part", "IN-USE" => "In Service", "DISPOSED" => "Disposed" }.freeze
  # What "since overhaul" counts from, and how logbooks abbreviate it.
  OVERHAUL_KINDS = { "major" => "Major overhaul", "factory_overhaul" => "Factory overhaul", "factory_new" => "Factory new or rebuilt (zero time)" }.freeze
  OVERHAUL_ABBREVIATIONS = { "major" => "SMOH", "factory_overhaul" => "SFOH", "factory_new" => "SNEW" }.freeze

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
  has_and_belongs_to_many :inspection_types
  has_and_belongs_to_many :airworthiness_directives

  validates :manufacturer, :model, :date_in_service, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :overhaul_kind, inclusion: { in: OVERHAUL_KINDS.keys }, allow_blank: true
  validate :parent_on_same_aircraft

  scope :in_use, -> { where(status: "IN-USE") }

  def to_s
    [ component_type&.name, install_location.presence && "(#{install_location})" ].compact.join(" ")
  end

  def status_label = STATUSES[status]
  def since_overhaul_abbreviation = OVERHAUL_ABBREVIATIONS.fetch(overhaul_kind, "TSO")
  def engine? = component_type&.name.to_s.match?(/engine/i)
  def propeller? = component_type&.name.to_s.match?(/propell?er|\bprop\b/i)

  def hours_to_tbo
    tbo_hours - hours_since_overhaul if tbo_hours
  end

  def hours_to_replacement
    replacement_hours - hours_since_overhaul if replacement_hours
  end

  # Past the date marked on the part (it may be used through that date).
  def expired?(today = Date.current) = expires_on.present? && today > expires_on

  def next_replacement_date
    overhaul_date + replacement_days.days if replacement_days && overhaul_date
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
    errors.add(:parent_component, "can't be itself") if parent_component_id == id && id
    errors.add(:parent_component, "must be on the same aircraft") if parent_component.aircraft_id != aircraft_id
  end
end

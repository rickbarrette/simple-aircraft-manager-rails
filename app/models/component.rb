class Component < ApplicationRecord
  STATUSES = { "SPARE" => "Spare Part", "IN-USE" => "In Service", "DISPOSED" => "Disposed" }.freeze

  belongs_to :aircraft, optional: true
  belongs_to :parent_component, class_name: "Component", optional: true
  belongs_to :component_type
  has_many :child_components, class_name: "Component", foreign_key: :parent_component_id, dependent: :destroy
  has_many :squawks, dependent: :nullify
  has_and_belongs_to_many :inspection_types
  has_and_belongs_to_many :airworthiness_directives

  validates :manufacturer, :model, :date_in_service, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validate :parent_on_same_aircraft

  scope :in_use, -> { where(status: "IN-USE") }

  def to_s
    [ component_type&.name, install_location.presence && "(#{install_location})" ].compact.join(" ")
  end

  def status_label = STATUSES[status]

  def hours_to_tbo
    tbo_hours - hours_since_overhaul if tbo_hours
  end

  def hours_to_replacement
    replacement_hours - hours_since_overhaul if replacement_hours
  end

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

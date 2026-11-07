class Aircraft < ApplicationRecord
  STATUSES = {
    "AVAILABLE" => "Available",
    "MX" => "In Maintenance",
    "GROUND" => "Grounded",
    "UNAVAILABLE" => "Unavailable"
  }.freeze

  has_one_attached :picture

  has_many :roles, class_name: "AircraftRole", dependent: :destroy
  has_many :users, through: :roles
  has_many :notes, class_name: "AircraftNote", dependent: :destroy
  has_many :events, class_name: "AircraftEvent", dependent: :delete_all
  has_many :share_tokens, dependent: :destroy
  has_many :components, dependent: :destroy
  has_many :squawks, dependent: :destroy
  has_many :logbook_entries, dependent: :destroy
  has_many :logbook_imports, dependent: :destroy
  has_many :document_collections, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :inspection_records, dependent: :destroy
  has_many :ad_compliances, dependent: :destroy
  has_many :major_records, dependent: :destroy
  has_many :flight_logs, dependent: :destroy
  has_many :consumable_records, dependent: :destroy
  has_many :oil_analyses, dependent: :destroy
  has_and_belongs_to_many :inspection_types
  has_and_belongs_to_many :airworthiness_directives

  # Which clock counts as time in service for maintenance (14 CFR 1.1 defines
  # it as takeoff to landing; many owners use tach, some Hobbs).
  TIME_BASES = { "tach" => "Tach", "hobbs" => "Hobbs" }.freeze

  validates :tail_number, presence: true
  validates :time_basis, inclusion: { in: TIME_BASES.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :icao_type, format: { with: /\A[A-Z0-9]{1,4}\z/, message: "must be an ICAO type designator like C150" }, allow_blank: true
  normalizes :icao_type, with: ->(t) { t.strip.upcase.presence }
  validate :picture_is_image

  scope :ordered, -> { order(:tail_number) }

  def to_s = tail_number

  def status_label = STATUSES[status]

  # Time in service used for maintenance: the chosen clock minus its offset
  # (as in the original, offsets cover a replaced meter).
  def current_hours
    hobbs? ? hobbs_time - hobbs_time_offset : tach_time - tach_time_offset
  end

  def hobbs? = time_basis == "hobbs"
  def time_basis_label = TIME_BASES[time_basis]

  def airworthiness
    @airworthiness ||= Airworthiness.new(self).call
  end

  def reload(*)
    @airworthiness = nil
    super
  end

  # ADs that apply directly or via any installed component.
  def applicable_ads
    AirworthinessDirective.applicable_to(self)
  end

  def applicable_inspection_types
    InspectionType.applicable_to(self)
  end

  def log_event!(category, event_name, user: Current.user, notes: nil)
    events.create!(category: category, event_name: event_name, user: user, notes: notes)
  end

  private

  def picture_is_image
    if picture.attached? && !picture.content_type.to_s.start_with?("image/")
      errors.add(:picture, "must be an image")
    end
  end
end

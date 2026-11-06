# A spectrographic oil analysis lab report for one oil sample.
class OilAnalysis < ApplicationRecord
  include UploadValidation

  # Element → [label, what it usually indicates].
  ELEMENTS = {
    "iron" => [ "Iron", "Cylinders, cam, lifters, gears" ],
    "copper" => [ "Copper", "Bearings, bushings, oil cooler" ],
    "nickel" => [ "Nickel", "Valve guides, cylinder plating" ],
    "chromium" => [ "Chromium", "Rings, chromed cylinders" ],
    "silver" => [ "Silver", "Bearing plating" ],
    "magnesium" => [ "Magnesium", "Accessory case, additive" ],
    "aluminum" => [ "Aluminum", "Pistons, case" ],
    "lead" => [ "Lead", "Fuel (100LL) blow-by" ],
    "silicon" => [ "Silicon", "Dirt (air filter), sealant" ],
    "titanium" => [ "Titanium", "Hardened parts" ],
    "tin" => [ "Tin", "Bearings, piston pin bushings" ],
    "molybdenum" => [ "Moly", "Rings, additive" ]
  }.freeze
  STATUSES = { "normal" => "Normal", "elevated" => "Elevated", "high" => "High" }.freeze
  # A reading this far above the lab's average for similar engines gets flagged.
  FLAG_RATIO = 1.5
  # Wear metals worth charting together (lead is on its own scale: it comes from fuel).
  TREND_ELEMENTS = %w[iron copper nickel chromium aluminum silicon tin].freeze

  belongs_to :aircraft
  belongs_to :component, optional: true
  has_one_attached :report

  validates :sample_date, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates(*ELEMENTS.keys.flat_map { [ _1, :"#{_1}_avg" ] }, :engine_hours, :oil_hours, :filter_hours, :oil_added,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true)
  validate :component_belongs_to_aircraft
  validates_uploads :report

  normalizes :lab, :sample_number, with: ->(v) { v.strip.presence }

  scope :recent_first, -> { order(sample_date: :desc, created_at: :desc) }

  def self.element_label(el) = ELEMENTS.fetch(el)[0]

  def value(el) = self[el]
  def average(el) = self[:"#{el}_avg"]

  # Above the lab average by FLAG_RATIO (needs an average to compare against).
  def flagged?(el)
    v, avg = value(el), average(el)
    v && avg&.positive? && v >= avg * FLAG_RATIO
  end

  def flagged_elements = ELEMENTS.keys.select { flagged?(_1) }
  def any_results? = ELEMENTS.keys.any? { value(_1) }

  private

  def component_belongs_to_aircraft
    errors.add(:component, "must be on this aircraft") if component && component.aircraft_id != aircraft_id
  end
end

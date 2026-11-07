# A spectrographic oil analysis lab report for one oil sample.
#
# Results are stored per element ({ "iron" => 44.0, … } in ppm), with the lab's
# average for similar engines alongside, so any lab's element list fits (AvLab
# tests 12 elements, Blackstone 20). Oil properties (viscosity, flash point,
# fuel/water %) are stored the same way.
class OilAnalysis < ApplicationRecord
  include UploadValidation

  # Element → [label, what it usually indicates]. The first twelve are the
  # wear-metal set every lab reports; the rest are mostly oil additives.
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
    "molybdenum" => [ "Moly", "Rings, additive" ],
    "manganese" => [ "Manganese", "Steel alloys (valves, gears)" ],
    "potassium" => [ "Potassium", "Coolant, additive" ],
    "boron" => [ "Boron", "Additive" ],
    "sodium" => [ "Sodium", "Additive, dirt" ],
    "calcium" => [ "Calcium", "Detergent additive" ],
    "phosphorus" => [ "Phosphorus", "Anti-wear additive" ],
    "zinc" => [ "Zinc", "Anti-wear additive, brass" ],
    "barium" => [ "Barium", "Additive" ]
  }.freeze
  COMMON_ELEMENTS = ELEMENTS.keys.first(12).freeze
  # Property → [label, unit].
  PROPERTIES = {
    "viscosity_sus_210f" => [ "Viscosity @ 210°F", "SUS" ],
    "viscosity_cst_100c" => [ "Viscosity @ 100°C", "cSt" ],
    "flashpoint_f" => [ "Flash point", "°F" ],
    "fuel_percent" => [ "Fuel", "%" ],
    "antifreeze_percent" => [ "Antifreeze", "%" ],
    "water_percent" => [ "Water", "%" ],
    "insolubles_percent" => [ "Insolubles", "%" ],
    "total_base_number" => [ "TBN", "" ],
    "total_acid_number" => [ "TAN", "" ]
  }.freeze
  STATUSES = { "normal" => "Normal", "monitor" => "Monitor", "action_required" => "Action required" }.freeze
  # A reading this far above the lab's average for similar engines gets flagged.
  FLAG_RATIO = 1.5
  # Wear metals worth charting together (lead is on its own scale: it comes from fuel).
  TREND_ELEMENTS = %w[iron copper nickel chromium aluminum silicon tin].freeze

  belongs_to :aircraft
  belongs_to :component, optional: true
  has_one_attached :report

  validates :sample_date, presence: true
  validates :status, inclusion: { in: STATUSES.keys }, allow_nil: true
  validates :engine_hours, :oil_hours, :filter_hours, :oil_added, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :results_are_numbers
  validate :component_belongs_to_aircraft
  validates_uploads :report

  normalizes :lab, :sample_number, :oil_type, with: ->(v) { v.strip.presence }
  normalizes :status, with: ->(v) { v.presence }

  scope :recent_first, -> { order(sample_date: :desc, created_at: :desc) }

  def self.element_label(el) = ELEMENTS.fetch(el)[0]

  # Elements any of these samples has a reading for, in display order.
  def self.elements_in(analyses) = ELEMENTS.keys.select { |el| analyses.any? { _1.value(el) } }

  def elements = super || {}
  def element_averages = super || {}
  def oil_properties = super || {}

  # Accept form or parser input: blanks dropped, numbers kept as numbers.
  def elements=(values)
    super(clean(values, ELEMENTS, :elements))
  end

  def element_averages=(values)
    super(clean(values, ELEMENTS, :element_averages))
  end

  def oil_properties=(values)
    super(clean(values, PROPERTIES, :oil_properties))
  end

  def value(el) = elements[el]
  def average(el) = element_averages[el]
  def property(key) = oil_properties[key]

  # Above the lab average by FLAG_RATIO (needs an average to compare against).
  def flagged?(el)
    v, avg = value(el), average(el)
    v && avg&.positive? && v >= avg * FLAG_RATIO
  end

  def flagged_elements = ELEMENTS.keys.select { flagged?(_1) }
  def any_results? = elements.any?
  def status_label = STATUSES[status]

  private

  def clean(values, allowed, attribute)
    (@invalid_results ||= {})[attribute] = []
    values.to_h.each_with_object({}) do |(key, raw), out|
      key = key.to_s
      next unless allowed.key?(key)
      next if raw.blank?
      number = raw.is_a?(Numeric) ? raw.to_f : Float(raw.to_s.strip, exception: false)
      if number && number >= 0
        out[key] = number
      else
        @invalid_results[attribute] << key
      end
    end
  end

  def results_are_numbers
    (@invalid_results || {}).each do |attribute, keys|
      labels = keys.map { (ELEMENTS[_1] || PROPERTIES[_1]).first }
      errors.add(attribute, "must be numbers of 0 or more (#{labels.to_sentence})") if keys.any?
    end
  end

  def component_belongs_to_aircraft
    errors.add(:component, "must be on this aircraft") if component && component.aircraft_id != aircraft_id
  end
end

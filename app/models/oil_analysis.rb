# A spectrographic oil analysis lab report for one oil sample.
#
# Results are stored per element ({ "iron" => 44.0, … } in ppm), with the lab's
# average for similar engines alongside, so any lab's element list fits (AvLab
# tests 12 elements, Blackstone 20). Oil properties (viscosity, flash point,
# fuel/water %) are stored the same way.
class OilAnalysis < ApplicationRecord
  include UploadValidation

  # Elements (labels.oil_analysis.elements) and what each usually indicates
  # (element_sources). The first twelve are the wear-metal set every lab
  # reports; the rest are mostly oil additives.
  ELEMENTS = LabelSet.new("oil_analysis.elements", %w[iron copper nickel chromium silver magnesium aluminum lead silicon titanium tin molybdenum manganese potassium boron sodium calcium phosphorus zinc barium])
  ELEMENT_SOURCES = LabelSet.new("oil_analysis.element_sources", ELEMENTS.keys)
  COMMON_ELEMENTS = ELEMENTS.keys.first(12).freeze
  # Oil properties (labels.oil_analysis.properties) and their units.
  PROPERTIES = LabelSet.new("oil_analysis.properties", %w[viscosity_sus_210f viscosity_cst_100c flashpoint_f fuel_percent antifreeze_percent water_percent insolubles_percent total_base_number total_acid_number])
  PROPERTY_UNITS = {
    "viscosity_sus_210f" => "SUS",
    "viscosity_cst_100c" => "cSt",
    "flashpoint_f" => "°F",
    "fuel_percent" => "%",
    "antifreeze_percent" => "%",
    "water_percent" => "%",
    "insolubles_percent" => "%",
    "total_base_number" => "",
    "total_acid_number" => ""
  }.freeze
  STATUSES = LabelSet.new("oil_analysis.statuses", %w[normal monitor action_required])
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

  def self.element_label(el) = ELEMENTS.fetch(el)

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
      labels = keys.map { ELEMENTS[_1] || PROPERTIES[_1] }
      errors.add(attribute, :not_numbers, fields: labels.to_sentence) if keys.any?
    end
  end

  def component_belongs_to_aircraft
    errors.add(:component, :other_aircraft) if component && component.aircraft_id != aircraft_id
  end
end

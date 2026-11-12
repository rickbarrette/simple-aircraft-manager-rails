# One import of ADs from an FAA DRS export, and which of the aircraft's
# models it covered. Together they're the AD baseline; the weekly
# Federal Register search covers what's published after.
class DrsImport < ApplicationRecord
  belongs_to :aircraft
  belongs_to :user, optional: true

  RENEW_AFTER = 12.months

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def self.normalize(model) = model.to_s.upcase.gsub(/[\s\-]/, "")

  # The aircraft's own models worth a DRS search: airframe, engines, propellers.
  def self.models_for(aircraft)
    ([ aircraft.model ] + aircraft.components.in_use.includes(:component_type)
                                  .select { _1.component_type&.name.to_s.match?(AdWatch::ENGINE_OR_PROP) }.map(&:model))
      .map { _1.to_s.strip }.compact_blank.uniq
  end

  # Which of the aircraft's models appear in the file's model lists ("O-200A" matches "O-200-A").
  def self.covered(aircraft, file_models)
    listed = file_models.map { normalize(_1) }.to_set
    models_for(aircraft).select { listed.include?(normalize(_1)) }
  end

  # Models never covered by an import.
  def self.missing_models(aircraft)
    done = aircraft.drs_imports.flat_map { Array(_1.models_covered) }.map { normalize(_1) }.to_set
    models_for(aircraft).reject { done.include?(normalize(_1)) }
  end

  def self.renewal_due?(aircraft)
    latest = aircraft.drs_imports.latest_first.first
    latest.nil? ? AirworthinessDirective.applicable_to(aircraft).exists? || aircraft.components.any? : latest.created_at < RENEW_AFTER.ago
  end
end

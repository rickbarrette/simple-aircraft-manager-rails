# The aircraft's maintenance status as 14 CFR 91.417(a)(2) lists it:
# total time in service (airframe, engines, propellers), life-limited parts,
# time since overhaul, inspection status, AD status and major alterations.
class MaintenanceReport
  attr_reader :aircraft, :generated_at

  def initialize(aircraft)
    @aircraft = aircraft
    @generated_at = Time.current
  end

  def time_in_service = aircraft.current_hours

  # Engines and propellers, by component type name.
  def engines = major_components(/engine/i)
  def propellers = major_components(/propell?er|\bprop\b/i)

  # Parts with a mandatory replacement time (life limits).
  def life_limited
    in_use.select { |c| (c.replacement_critical? && (c.replacement_hours || c.replacement_days)) || c.expires_on }
  end

  # Items overhauled on a time basis.
  def overhaul_items
    in_use.select { |c| c.tbo_hours || c.tbo_days }
  end

  def inspections = @inspections ||= Compliance.inspection_rows(aircraft)
  def ads = @ads ||= Compliance.ad_rows(aircraft)
  def major_records = aircraft.major_records.recent_first.includes(:component, :form_337_document, :stc_document)
  def open_squawks = aircraft.squawks.active.by_priority.includes(:component)
  def airworthiness = aircraft.airworthiness

  private

  def in_use = @in_use ||= aircraft.components.in_use.includes(:component_type).order(:install_location).to_a

  def major_components(pattern) = in_use.select { |c| c.component_type&.name.to_s.match?(pattern) }
end

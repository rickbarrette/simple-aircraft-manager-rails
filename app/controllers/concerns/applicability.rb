# ADs and inspection types are shared reference data that can apply to many
# aircraft. From an aircraft's page we only ever touch *this* aircraft's links:
# the airframe itself and/or some of its components.
module Applicability
  extend ActiveSupport::Concern

  private

  def apply_applicability(record, to_airframe:, component_ids:)
    mine = @aircraft.components.where(id: Array(component_ids).compact_blank).to_a
    others = record.components.where.not(aircraft_id: @aircraft.id).to_a
    record.components = others + mine
    if to_airframe
      record.aircraft << @aircraft unless record.aircraft.include?(@aircraft)
    else
      record.aircraft.delete(@aircraft)
    end
    # Never let a record silently drop off this aircraft entirely.
    record.aircraft << @aircraft if mine.empty? && !to_airframe
  end

  def detach_from_aircraft(record)
    record.aircraft.delete(@aircraft)
    record.components.delete(*record.components.where(aircraft_id: @aircraft.id))
    record.destroy if record.aircraft.empty? && record.components.empty? && orphan_deletable?(record)
  end

  def orphan_deletable?(record)
    case record
    when AirworthinessDirective then record.ad_compliances.none?
    when InspectionType then record.inspection_records.none?
    else false
    end
  end

  def applies_to_airframe? = params[:applies_to_airframe] == "1"
  def applicable_component_ids = params[:component_ids]
end

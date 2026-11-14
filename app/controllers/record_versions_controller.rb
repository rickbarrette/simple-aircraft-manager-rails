# Every change to the aircraft's maintenance records (AC 120-78B 3.2.2).
class RecordVersionsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, only: :restore

  SHARED = { "AirworthinessDirective" => AirworthinessDirective, "InspectionType" => InspectionType }.freeze

  def index
    @type = params[:type].presence_in(RecordVersion.where(aircraft_id: @aircraft.id).distinct.pluck(:item_type))
    scope = RecordVersion.where(aircraft_id: @aircraft.id).order(id: :desc).includes(:user)
    scope = scope.where(item_type: @type) if @type
    @versions = scope.limit(500)
    @types = RecordVersion.where(aircraft_id: @aircraft.id).distinct.pluck(:item_type).sort
  end

  # Puts back an AD or inspection type link that was removed (the removal
  # stays in the history, and the restore is recorded as a new link).
  def restore
    version = RecordVersion.where(aircraft_id: @aircraft.id, event: "unlink", item_type: SHARED.keys).find(params[:id])
    record = SHARED.fetch(version.item_type).find_by(id: version.item_id)
    return redirect_to(aircraft_record_versions_path(@aircraft), alert: t("flash.record_versions.that_record_no_longer")) unless record
    c = version.changes_hash
    if c["applies_to"] == "component"
      component = @aircraft.components.find_by(id: c["component_id"])
      return redirect_to(aircraft_record_versions_path(@aircraft), alert: t("flash.record_versions.that_component_no_longer")) unless component
      record.components << component unless record.components.include?(component)
    else
      record.aircraft << @aircraft unless record.aircraft.include?(@aircraft)
    end
    log_event(version.item_type == "AirworthinessDirective" ? "ad" : "inspection", "Restored: #{record} applies again")
    redirect_to aircraft_record_versions_path(@aircraft), notice: t("flash.record_versions.applies_to_again", record: record, tail_number: @aircraft.tail_number)
  end

  # Whether an unlink can still be undone (the record exists and isn't linked that way now).
  def self.restorable?(version, aircraft)
    return false unless version.event == "unlink" && SHARED.key?(version.item_type)
    record = SHARED[version.item_type].find_by(id: version.item_id) or return false
    c = version.changes_hash
    if c["applies_to"] == "component"
      record.component_ids.exclude?(c["component_id"]) && aircraft.components.exists?(id: c["component_id"])
    else
      record.aircraft_ids.exclude?(aircraft.id)
    end
  end
end

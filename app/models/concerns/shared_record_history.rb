# Record history for records shared between aircraft (ADs and inspection
# types). Their applicability lives in plain join tables, so linking one to
# an aircraft or a component, unlinking it, and changes to the shared record
# are written to each affected aircraft's history chain here (AC 120-78B 3.2.2;
# for ADs, the AD status kept under 14 CFR 91.417(a)(2)(v)).
module SharedRecordHistory
  extend ActiveSupport::Concern

  IGNORED = %w[created_at updated_at].freeze

  included do
    has_and_belongs_to_many :aircraft, after_add: :history_link_aircraft, after_remove: :history_unlink_aircraft
    has_and_belongs_to_many :components, after_add: :history_link_component, after_remove: :history_unlink_component
    after_update { (c = saved_changes.except(*IGNORED)).any? && linked_aircraft_ids.each { |id| history!(id, "update", c) } }
    before_destroy { linked_aircraft_ids.each { |id| history!(id, "destroy", attributes.except(*IGNORED)) } }
  end

  class_methods do
    # Records that apply to the aircraft directly, or to one of its components.
    def applicable_to(aircraft)
      direct = joins(:aircraft).where(aircraft: { id: aircraft.id }).select(:id)
      via_component = joins(:components).where(components: { aircraft_id: aircraft.id }).select(:id)
      where(id: direct).or(where(id: via_component))
    end
  end

  # Aircraft this record applies to, directly or through a component.
  def linked_aircraft_ids = (aircraft_ids + components.map(&:aircraft_id)).compact.uniq

  # Logs that a component it applied to is being deleted (the join row goes
  # with the component, without the callbacks above).
  def history_component_deleted(component) = history_link(component.aircraft_id, "unlink", component, reason: "component deleted")

  private

  def history_link_aircraft(aircraft) = history_link(aircraft.id, "link", nil)
  def history_unlink_aircraft(aircraft) = history_link(aircraft.id, "unlink", nil)
  def history_link_component(component) = history_link(component.aircraft_id, "link", component)
  def history_unlink_component(component) = history_link(component.aircraft_id, "unlink", component)

  def history_link(aircraft_id, event, component, reason: nil)
    return unless persisted? && aircraft_id
    changes = { "record" => to_s, "applies_to" => component ? "component" : "airframe" }
    changes.merge!("component_id" => component.id, "component" => "#{component} #{component.model}".strip) if component
    changes["reason"] = reason if reason
    history!(aircraft_id, event, changes)
  end

  def history!(aircraft_id, event, changes)
    RecordVersion.append!(item: self, aircraft_id: aircraft_id, event: event, changes: changes.as_json)
  end
end

# Keeps every change to the record as a RecordVersion (AC 120-78B 3.2.2):
# full values on create and destroy, [before, after] for each changed field.
module Versioned
  extend ActiveSupport::Concern

  IGNORED = %w[created_at updated_at].freeze

  included do
    has_many :versions, -> { chronological }, as: :item, class_name: "RecordVersion", inverse_of: false
    after_create { record_version!("create", attributes.except(*IGNORED)) }
    after_update { (c = saved_changes.except(*IGNORED)).any? && record_version!("update", c) }
    after_destroy { record_version!("destroy", attributes.except(*IGNORED)) }
  end

  private

  def record_version!(event, changes)
    RecordVersion.append!(item: self, aircraft_id: versioned_aircraft_id, event: event, changes: changes.as_json)
  end

  def versioned_aircraft_id
    return aircraft_id if has_attribute?(:aircraft_id) && aircraft_id
    return component&.aircraft_id if respond_to?(:component)
    logbook_entry&.aircraft_id if respond_to?(:logbook_entry)
  end
end

# What a role on an aircraft can do (Role#permissions). Grouped the way the
# app is laid out; labels and descriptions are in config/locales
# (permissions.<key>.label / .description). Seeing an aircraft's records
# needs no permission: every role can view everything on its aircraft.
module Permission
  GROUPS = {
    flying: %w[log_flights update_hours import_flights edit_own_flights edit_any_flight delete_flights],
    squawks_and_notes: %w[report_squawks defer_squawks manage_squawks write_notes manage_notes record_consumables manage_consumables],
    maintenance: %w[write_logbook sign_logbook manage_components manage_inspections manage_ads manage_major_records
                    manage_weight_balance manage_documents record_oil_analyses manage_oil_analyses],
    data: %w[import_records export_data restore_history],
    aircraft: %w[edit_aircraft delete_aircraft manage_people manage_sharing],
    notifications: %w[receive_reminders]
  }.freeze

  ALL = GROUPS.values.flatten.freeze

  # The built-in roles' permissions when first created (admins can change all
  # but Owner's, which always has every permission). Pilot is what pilots
  # could do before roles were configurable.
  DEFAULTS = {
    "pilot" => %w[log_flights update_hours edit_own_flights report_squawks defer_squawks write_notes record_consumables
                  record_oil_analyses sign_logbook],
    "mechanic" => %w[update_hours report_squawks defer_squawks manage_squawks write_notes manage_notes record_consumables
                     manage_consumables write_logbook sign_logbook manage_components manage_inspections manage_ads
                     manage_major_records manage_weight_balance manage_documents record_oil_analyses manage_oil_analyses
                     receive_reminders],
    "viewer" => []
  }.freeze

  def self.label(key) = I18n.t("permissions.#{key}.label")
  def self.description(key) = I18n.t("permissions.#{key}.description")
  def self.group_label(group) = I18n.t("permissions.groups.#{group}")
end

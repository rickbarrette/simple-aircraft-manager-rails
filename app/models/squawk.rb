class Squawk < ApplicationRecord
  include UploadValidation

  PRIORITIES = { 0 => "Ground Aircraft", 1 => "Fix Soon", 2 => "Fix at Next Inspection", 3 => "Fix Eventually" }.freeze
  PRIORITY_COLORS = { 0 => "red", 1 => "orange", 2 => "blue", 3 => "gray" }.freeze

  belongs_to :aircraft
  belongs_to :component, optional: true
  belongs_to :reported_by, class_name: "User", optional: true
  belongs_to :logbook_entry, optional: true
  has_many_attached :attachments

  validates :priority, inclusion: { in: PRIORITIES.keys }
  validates :issue_reported, presence: true
  validates_uploads :attachments

  scope :active, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :by_priority, -> { order(:priority, created_at: :desc) }

  # Deferring inoperative equipment without an MEL, 14 CFR 91.213(d): what
  # was done with the item and who decided it isn't a hazard.
  DEFERRAL_ACTIONS = { "deactivated" => "Deactivated and placarded \"Inoperative\"",
                       "removed" => "Removed, cockpit control placarded \"Inoperative\"" }.freeze
  DEFERRAL_ROLES = { "pilot" => "Pilot", "mechanic" => "Certificated mechanic" }.freeze
  # Each must be confirmed to defer (91.213(d)(2)(i)–(iv) and (d)(3)–(4)).
  DEFERRAL_CHECKS = {
    "not_required_by_type" => "Not part of the VFR-day type certification instruments and equipment, nor on the aircraft's equipment list or kinds of operations equipment list",
    "not_required_by_rules" => "Not required by 91.205 or any other rule for the kind of flight planned",
    "not_required_by_ad" => "Not required by an airworthiness directive",
    "placarded" => "Removed or deactivated, and placarded \"Inoperative\"",
    "no_hazard" => "A pilot or certificated mechanic has determined it isn't a hazard to the aircraft"
  }.freeze

  scope :deferred, -> { active.where.not(deferred_at: nil) }

  validates :deferral_action, inclusion: { in: DEFERRAL_ACTIONS.keys }, if: :deferred?
  validates :deferred_by_role, inclusion: { in: DEFERRAL_ROLES.keys }, if: :deferred?
  validates :deferred_by_name, presence: true, if: :deferred?

  def priority_label = deferred? ? "Deferred (91.213(d))" : PRIORITIES[priority]
  def priority_color = deferred? ? "blue" : PRIORITY_COLORS[priority]
  def deferred? = deferred_at.present? && !resolved?
  def grounding? = priority.zero? && !resolved? && !deferred?
  def deferral_action_label = DEFERRAL_ACTIONS[deferral_action]

  # Defers the item if every check is confirmed; returns false with errors otherwise.
  def defer(checks:, name:, role:, action:, notes: nil)
    missing = DEFERRAL_CHECKS.keys - Array(checks).map(&:to_s)
    assign_attributes(deferred_at: Time.current, deferred_by_name: name.to_s.strip.presence, deferred_by_role: role,
                      deferral_action: action, deferral_notes: notes.to_s.strip.presence)
    missing.each { errors.add(:base, "Confirm: #{DEFERRAL_CHECKS[_1]}") }
    return false if missing.any? || !valid?
    save
  end

  def undefer! = update!(deferred_at: nil, deferred_by_name: nil, deferred_by_role: nil, deferral_action: nil, deferral_notes: nil)

  def resolve!(notes: nil, logbook_entry: nil)
    update!(resolved: true, resolved_at: Time.current, logbook_entry: logbook_entry || self.logbook_entry,
            notes: [ self.notes, notes ].compact_blank.join("\n\n"))
  end
end

class Squawk < ApplicationRecord
  include Versioned
  include UploadValidation

  PRIORITIES = LabelSet.new("squawk.priorities", [ 0, 1, 2, 3 ])
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
  DEFERRAL_ACTIONS = LabelSet.new("squawk.deferral_actions", %w[deactivated removed])
  DEFERRAL_ROLES = LabelSet.new("squawk.deferral_roles", %w[pilot mechanic])
  # Each must be confirmed to defer (91.213(d)(2)(i)–(iv) and (d)(3)–(4)).
  DEFERRAL_CHECKS = LabelSet.new("squawk.deferral_checks", %w[not_required_by_type not_required_by_rules not_required_by_ad placarded no_hazard])

  scope :deferred, -> { active.where.not(deferred_at: nil) }

  validates :deferral_action, inclusion: { in: DEFERRAL_ACTIONS.keys }, if: :deferred?
  validates :deferred_by_role, inclusion: { in: DEFERRAL_ROLES.keys }, if: :deferred?
  validates :deferred_by_name, presence: true, if: :deferred?

  def priority_label = deferred? ? I18n.t("models.squawk.deferred") : PRIORITIES[priority]
  def priority_color = deferred? ? "blue" : PRIORITY_COLORS[priority]
  def deferred? = deferred_at.present? && !resolved?
  def grounding? = priority.zero? && !resolved? && !deferred?
  def deferral_action_label = DEFERRAL_ACTIONS[deferral_action]

  # Defers the item if every check is confirmed; returns false with errors otherwise.
  def defer(checks:, name:, role:, action:, notes: nil)
    missing = DEFERRAL_CHECKS.keys - Array(checks).map(&:to_s)
    assign_attributes(deferred_at: Time.current, deferred_by_name: name.to_s.strip.presence, deferred_by_role: role,
                      deferral_action: action, deferral_notes: notes.to_s.strip.presence)
    missing.each { errors.add(:base, :confirm, check: DEFERRAL_CHECKS[_1]) }
    return false if missing.any? || !valid?
    save
  end

  def undefer! = update!(deferred_at: nil, deferred_by_name: nil, deferred_by_role: nil, deferral_action: nil, deferral_notes: nil)

  def resolve!(notes: nil, logbook_entry: nil)
    update!(resolved: true, resolved_at: Time.current, logbook_entry: logbook_entry || self.logbook_entry,
            notes: [ self.notes, notes ].compact_blank.join("\n\n"))
  end
end

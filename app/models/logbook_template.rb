# Wording to start a logbook entry from (Admin → Logbook templates). Picking
# one on the entry form fills the text and, when set, the entry type, the
# logbook and the kind of certificate.
class LogbookTemplate < ApplicationRecord
  DEFAULTS_FILE = Rails.root.join("config/logbook_templates.yml")

  validates :name, :text, presence: true
  validates :entry_type, inclusion: { in: LogbookEntry::ENTRY_TYPES.keys }
  validates :log_type, inclusion: { in: LogbookEntry::LOG_TYPES.keys }, allow_blank: true
  validates :certificate_type, inclusion: { in: LogbookEntry::CERTIFICATE_TYPES.keys }, allow_blank: true
  normalizes :log_type, :certificate_type, :reference, with: ->(v) { v.strip.presence }

  scope :ordered, -> { order(:position, :name) }

  def label = reference.present? ? "#{name} — #{reference}" : name

  def self.defaults = YAML.safe_load_file(DEFAULTS_FILE)

  # Adds the built-in templates that aren't here (matched by name). Returns
  # how many were added.
  def self.restore_defaults!
    existing = pluck(:name).to_set
    next_position = (maximum(:position) || 0) + 1
    added = defaults.reject { existing.include?(_1["name"]) }
    added.each_with_index { |d, i| create!(d.slice("name", "reference", "text", "log_type", "certificate_type").merge("position" => next_position + i)) }
    added.size
  end

  # The built-in set, once: after that, admins' deletions stick.
  def self.ensure_defaults!
    return if Setting.integer("logbook_templates_seeded") == 1
    transaction do
      restore_defaults!
      Setting.update_integers("logbook_templates_seeded" => "1")
    end
  end
end

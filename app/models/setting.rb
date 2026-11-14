# App-wide settings an admin can change (Admin → Settings), stored as
# key/value rows. Read straight from the database each time, so a change
# applies to every server process at once.
#
#   Setting.max_upload_mb      # => 50
#   Setting.max_upload_bytes   # => 52428800
class Setting < ApplicationRecord
  INTEGERS = {
    "max_upload_mb" => { default: 50, in: 1..1024 },
    "backups_kept" => { default: 14, in: 1..365 },
    "offsite_backups_kept" => { default: 30, in: 1..365 },
    "documents_claude_text" => { default: 0, in: 0..1 },
    "logbook_templates_seeded" => { default: 0, in: 0..1 } # internal flag
  }.freeze
  LABELS = LabelSet.new("setting.keys", INTEGERS.keys)

  validates :key, presence: true, uniqueness: true, inclusion: { in: INTEGERS.keys }
  validate :value_in_range

  class << self
    def max_upload_mb = integer("max_upload_mb")
    def max_upload_bytes = max_upload_mb.megabytes

    def integer(key)
      definition = INTEGERS.fetch(key)
      value = find_by(key: key)&.value
      value.present? ? value.to_i.clamp(definition[:in]) : definition[:default]
    end

    # Saves several settings; returns the records (check #errors) or [].
    def update_integers(values)
      records = values.to_h.slice(*INTEGERS.keys).map do |key, value|
        find_or_initialize_by(key: key).tap { _1.value = value.to_s.strip }
      end
      transaction { records.each { _1.save || raise(ActiveRecord::Rollback) } }
      records
    end
  end

  private

  def value_in_range
    definition = INTEGERS[key] or return
    unless value.to_s.match?(/\A\d+\z/) && definition[:in].cover?(value.to_i)
      errors.add(:base, :out_of_range, setting: LABELS[key], min: definition[:in].min, max: definition[:in].max)
    end
  end
end

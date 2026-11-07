# Which software versions have run, and when (AC 120-78B 3.2.6): recorded
# when the app starts and by the nightly check.
class AppRevision < ApplicationRecord
  scope :latest_first, -> { order(first_seen_at: :desc) }

  def self.touch_current!
    revision = SystemInfo.new.revision
    return if revision.blank? || revision == "unknown"
    now = Time.current
    record = find_or_initialize_by(revision: revision)
    record.first_seen_at ||= now
    record.built_at ||= SystemInfo.new.built_at
    record.last_seen_at = now
    record.save!
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[app revisions] #{e.class}: #{e.message}")
  end
end

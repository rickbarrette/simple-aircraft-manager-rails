class BackupRun < ApplicationRecord
  scope :latest_first, -> { order(created_at: :desc) }
  def self.latest = latest_first.first
  def self.last_good = where(ok: true).latest_first.first
end

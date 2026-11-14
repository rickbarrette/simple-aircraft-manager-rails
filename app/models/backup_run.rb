class BackupRun < ApplicationRecord
  scope :latest_first, -> { order(created_at: :desc) }
  def self.latest = latest_first.first
end

class OffsiteRun < ApplicationRecord
  KINDS = %w[backup restore_test].freeze
  validates :kind, inclusion: { in: KINDS }

  scope :backups, -> { where(kind: "backup") }
  scope :restore_tests, -> { where(kind: "restore_test") }

  def self.latest_backup = backups.order(:created_at, :id).last
  def self.latest_restore_test = restore_tests.order(:created_at, :id).last
  def recent? = created_at > 2.days.ago
end

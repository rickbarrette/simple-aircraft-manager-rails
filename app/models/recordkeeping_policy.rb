# The facts the procedures document needs that the app can't know (who is
# responsible, where it's hosted, the off-site backup, how often to audit).
# One row for the installation.
class RecordkeepingPolicy < ApplicationRecord
  validates :audit_interval_months, numericality: { only_integer: true, in: 1..24 }
  validates :audit_sample_size, numericality: { only_integer: true, in: 1..50 }

  def self.current = first || create!

  def complete? = [ operator_name, responsible_name, hosting_description, offsite_backup_description ].all?(&:present?)
end

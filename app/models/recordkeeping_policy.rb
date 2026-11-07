# The facts the procedures document needs that the app can't know (who is
# responsible, where it's hosted, the off-site backup, how often to audit).
# One row for the installation.
class RecordkeepingPolicy < ApplicationRecord
  validates :audit_interval_months, numericality: { only_integer: true, in: 1..24 }
  validates :audit_sample_size, numericality: { only_integer: true, in: 1..50 }

  def self.current = first || create!

  def complete? = [ operator_name, responsible_name, hosting_description ].all?(&:present?) && offsite_backup? && unfilled_fields.empty?

  FILLABLE = { hosting_description: "Hosting and network", offsite_backup_description: "Off-site backup",
               additional_procedures: "Additional procedures", operator_name: "Owner / operator",
               responsible_name: "Responsible person", responsible_title: "Their role" }.freeze
  # A [bracketed] blank left from the suggested text (not a Markdown link).
  BLANK = /\[[^\]\n]+\](?!\()/

  # Labels of the fields that still have a blank to fill in.
  def unfilled_fields = FILLABLE.select { |attr, _| self[attr].to_s.match?(BLANK) }.values

  # Off-site backup is described, or done by the app to Google Drive.
  def offsite_backup? = offsite_backup_description.present? || OffsiteConnection.connected?
end

# A quality-control audit of the electronic records (AC 120-78B 3.2.8.5):
# a checklist, some items checked by the app, some confirmed by the auditor.
class AuditRun < ApplicationRecord
  belongs_to :performed_by, class_name: "User", optional: true

  scope :latest_first, -> { order(performed_at: :desc) }
  before_update { throw :abort }
  before_destroy { throw :abort }

  def self.latest = latest_first.first

  def self.next_due
    interval = RecordkeepingPolicy.current.audit_interval_months.months
    (latest&.performed_at || Time.current - interval).to_date + interval
  end

  def self.due_soon? = next_due <= 14.days.from_now.to_date
end

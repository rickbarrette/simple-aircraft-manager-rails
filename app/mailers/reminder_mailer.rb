class ReminderMailer < ApplicationMailer
  # [[aircraft, issues, new AD alerts], …] for the aircraft the user owns
  # that need attention.
  def self.items_for(user)
    Aircraft.joins(:roles).where(aircraft_roles: { user_id: user.id, role: "owner" }).ordered
            .map { [ _1, _1.airworthiness.issues, _1.ad_alerts.pending.to_a ] }.reject { _2.empty? && _3.empty? }
  end

  def self.expiring_certificates_for(user) = user.certificates.expiring.to_a

  def self.audit_due_for?(user) = user.admin? && AuditRun.due_soon?

  # Owned aircraft whose AD baseline needs a (new) DRS import: none yet, a
  # year old, or a model never covered.
  def self.drs_due_for(user)
    Aircraft.joins(:roles).where(aircraft_roles: { user_id: user.id, role: "owner" }).ordered
            .select { DrsImport.renewal_due?(_1) || DrsImport.missing_models(_1).any? }
  end

  # The DRS reminder rides along with any other news; on its own it's sent
  # on the first Monday of the month only, not every week.
  def self.anything_for?(user, today: Date.current)
    items_for(user).any? || expiring_certificates_for(user).any? || audit_due_for?(user) ||
      (today.day <= 7 && drs_due_for(user).any?)
  end

  def weekly(user)
    @user = user
    @items = self.class.items_for(user)
    @certificates = self.class.expiring_certificates_for(user)
    @audit_due = self.class.audit_due_for?(user) && AuditRun.next_due
    @drs_due = self.class.drs_due_for(user)
    overdue = @items.sum { |_, issues, _| issues.count { _1.severity.in?(%w[RED LIMITED]) } }
    subject = overdue.positive? ? t(".subject_overdue", count: overdue) : t(".subject_due")
    subject = t(@certificates.any? ? ".subject_certificate" : (@audit_due ? ".subject_audit" : ".subject_drs")) if @items.empty?
    mail subject: [ subject, @items.map { _1.first.tail_number }.to_sentence.presence ].compact.join(": "), to: user.email_address
  end
end

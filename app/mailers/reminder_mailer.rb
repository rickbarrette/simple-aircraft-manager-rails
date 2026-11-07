class ReminderMailer < ApplicationMailer
  # [[aircraft, issues], …] for the aircraft the user owns that need attention.
  def self.items_for(user)
    Aircraft.joins(:roles).where(aircraft_roles: { user_id: user.id, role: "owner" }).ordered
            .map { [ _1, _1.airworthiness.issues ] }.reject { _2.empty? }
  end

  def weekly(user)
    @user = user
    @items = self.class.items_for(user)
    overdue = @items.sum { |_, issues| issues.count { _1.severity.in?(%w[RED LIMITED]) } }
    subject = overdue.positive? ? "#{overdue} #{'item'.pluralize(overdue)} overdue" : "Maintenance coming due"
    mail subject: "#{subject}: #{@items.map { _1.first.tail_number }.to_sentence}", to: user.email_address
  end
end

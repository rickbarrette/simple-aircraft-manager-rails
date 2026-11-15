# The link of an invitation made for one email address (AccessInvitation).
class AccessInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @grants = invitation.grants.includes(:aircraft, :role).sort_by { _1.aircraft.tail_number }
    @url = join_url(token)
    mail subject: t(".subject", who: invitation.created_by&.display_name || t(".an_administrator")), to: invitation.email
  end
end

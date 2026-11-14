class SigningInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @entry = invitation.logbook_entry
    @url = invited_signing_url(token)
    mail subject: t(".subject", tail_number: @entry.aircraft.tail_number), to: invitation.email
  end
end

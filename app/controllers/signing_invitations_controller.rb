# An owner asks someone outside the aircraft (a mechanic) to sign an entry.
class SigningInvitationsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_entry
  rate_limit to: 10, within: 1.hour, only: :create, with: -> { redirect_back fallback_location: root_path, alert: t("flash.signing_invitations.too_many_invitations_try") }

  def new
    @invitation = @entry.signing_invitations.new
  end

  def create
    return redirect_to(aircraft_logbook_entry_path(@aircraft, @entry), alert: t("flash.signing_invitations.this_entry_is_already")) if @entry.signed?
    unless MailSettings.configured?
      return redirect_to aircraft_logbook_entry_path(@aircraft, @entry), alert: t("flash.signing_invitations.email_isn_t_set")
    end
    @invitation = @entry.signing_invitations.new(params.require(:signing_invitation).permit(:email, :message).merge(invited_by: current_user))
    if @invitation.save
      SigningInvitationMailer.invite(@invitation, @invitation.token).deliver_later
      if (invitee = User.active.find_by(email_address: @invitation.email))
        PushNotifier.notify(invitee, :signing_request, path: invited_signing_path(@invitation.token), tag: "sign-#{@invitation.id}",
                                                       tail: @aircraft.tail_number, name: current_user.display_name)
      end
      log_event("logbook", t("flash.signing_invitations.signature_requested_from_entry", email: @invitation.email, date: @entry.date))
      redirect_to aircraft_logbook_entry_path(@aircraft, @entry), notice: t("flash.signing_invitations.invitation_sent_to_the", email: @invitation.email, days: SigningInvitation::VALID_FOR.in_days.to_i)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_entry = @entry = @aircraft.logbook_entries.find(params[:logbook_entry_id])
end

# An owner asks someone outside the aircraft (a mechanic) to sign an entry.
class SigningInvitationsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_entry
  rate_limit to: 10, within: 1.hour, only: :create, with: -> { redirect_back fallback_location: root_path, alert: "Too many invitations; try again later." }

  def new
    @invitation = @entry.signing_invitations.new
  end

  def create
    return redirect_to(aircraft_logbook_entry_path(@aircraft, @entry), alert: "This entry is already signed.") if @entry.signed?
    unless MailSettings.configured?
      return redirect_to aircraft_logbook_entry_path(@aircraft, @entry), alert: "Email isn't set up, so invitations can't be sent (Admin → About)."
    end
    @invitation = @entry.signing_invitations.new(params.require(:signing_invitation).permit(:email, :message).merge(invited_by: current_user))
    if @invitation.save
      SigningInvitationMailer.invite(@invitation, @invitation.token).deliver_later
      log_event("logbook", "Signature requested from #{@invitation.email} (#{@entry.date} entry)")
      redirect_to aircraft_logbook_entry_path(@aircraft, @entry), notice: "Invitation sent to #{@invitation.email}. The link works once, for #{SigningInvitation::VALID_FOR.inspect}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_entry = @entry = @aircraft.logbook_entries.find(params[:logbook_entry_id])
end

# Invitation codes for one aircraft (AccessInvitation), from its Access page,
# by whoever manages its people: only the roles they can give (AircraftAccess).
class AircraftInvitationsController < ApplicationController
  include AircraftScoped
  requires_permission :manage_people

  def create
    role = AircraftAccess.new(@aircraft, actor: current_user).assignable_roles.find { _1.id == params[:role_id].to_i }
    return back(alert: t("services.aircraft_access.owner_only")) unless role
    attributes = params.permit(:label, :email, :name, :max_uses, :expires_at).to_h.symbolize_keys
    attributes[:label] = t("flash.aircraft_invitations.default_label", tail_number: @aircraft.tail_number) if attributes[:label].blank?
    @invitation = AccessInvitation.create_for(current_user, attributes, [ [ @aircraft, role ] ])
    return back(alert: @invitation.errors.full_messages.to_sentence) unless @invitation.persisted?
    log_event("role", t("flash.aircraft_invitations.created_event", role: role.name), notes: @invitation.label)
    render :created
  end

  # Only invitations for this aircraft alone; others are managed in Admin → Invitations.
  def destroy
    invitation = AccessInvitation.where(id: self.class.only_for(@aircraft)).find(params[:id])
    invitation.update!(revoked_at: Time.current)
    log_event("role", t("flash.aircraft_invitations.revoked_event"), notes: invitation.label)
    back(notice: t("flash.aircraft_invitations.revoked"))
  end

  # Ids of the invitations that give a role on this aircraft and no other.
  def self.only_for(aircraft)
    AccessInvitationRole.group(:access_invitation_id).having("COUNT(*) = 1 AND MAX(aircraft_id) = ?", aircraft.id).select(:access_invitation_id)
  end

  private

  def back(flash) = redirect_to(aircraft_aircraft_roles_path(@aircraft, anchor: "invitations"), flash)
end

class ShareTokensController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def create
    token = @aircraft.share_tokens.new(params.require(:share_token).permit(:label, :privilege, :expires_at))
    token.created_by = current_user
    if token.save
      log_event("aircraft", "Share link created (#{token.privilege})", notes: token.label)
      redirect_to aircraft_aircraft_roles_path(@aircraft), notice: "Share link created."
    else
      redirect_to aircraft_aircraft_roles_path(@aircraft), alert: token.errors.full_messages.to_sentence
    end
  end

  def destroy
    token = @aircraft.share_tokens.find(params[:id])
    token.destroy!
    log_event("aircraft", "Share link revoked", notes: token.label)
    redirect_to aircraft_aircraft_roles_path(@aircraft), notice: "Share link revoked."
  end
end

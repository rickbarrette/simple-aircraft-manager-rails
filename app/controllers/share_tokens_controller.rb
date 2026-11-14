class ShareTokensController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def create
    token = @aircraft.share_tokens.new(params.require(:share_token).permit(:label, :privilege, :expires_at))
    token.created_by = current_user
    if token.save
      log_event("aircraft", t("flash.share_tokens.share_link_created_2", privilege: token.privilege), notes: token.label)
      redirect_to aircraft_aircraft_roles_path(@aircraft), notice: t("flash.share_tokens.share_link_created")
    else
      redirect_to aircraft_aircraft_roles_path(@aircraft), alert: token.errors.full_messages.to_sentence
    end
  end

  def destroy
    token = @aircraft.share_tokens.find(params[:id])
    token.destroy!
    log_event("aircraft", t("flash.share_tokens.share_link_revoked_2"), notes: token.label)
    redirect_to aircraft_aircraft_roles_path(@aircraft), notice: t("flash.share_tokens.share_link_revoked")
  end
end

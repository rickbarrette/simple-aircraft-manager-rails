# Invitation codes for any aircraft, or none (an account only), by
# administrators (AccessInvitation).
class Admin::InvitationsController < ApplicationController
  before_action :require_admin!

  def index
    @invitations = AccessInvitation.recent_first.includes(:created_by, grants: %i[aircraft role]).limit(200)
  end

  def new
    @invitation = AccessInvitation.new(max_uses: 1, expires_at: AccessInvitation::VALID_FOR.from_now.change(sec: 0))
  end

  def create
    roles = Role.all.index_by(&:id)
    grants = Aircraft.where(id: params.fetch(:roles, {}).keys).filter_map do |aircraft|
      role = roles[params[:roles][aircraft.id.to_s].to_i]
      [ aircraft, role ] if role
    end
    @invitation = AccessInvitation.create_for(current_user, params.require(:access_invitation).permit(:label, :email, :name, :max_uses, :expires_at), grants)
    if @invitation.persisted?
      render :created
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    AccessInvitation.find(params[:id]).update!(revoked_at: Time.current)
    redirect_to admin_invitations_path, notice: t("flash.admin_invitations.revoked")
  end
end

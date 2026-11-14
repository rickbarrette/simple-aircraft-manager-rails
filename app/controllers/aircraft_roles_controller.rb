# Owner-only: manage who can access the aircraft, and its public share links.
class AircraftRolesController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def index
    @roles = @aircraft.roles.includes(:user).order(:role, :created_at)
    @share_tokens = @aircraft.share_tokens.order(created_at: :desc).includes(:created_by)
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    unless user
      return redirect_to aircraft_aircraft_roles_path(@aircraft),
                         alert: t("flash.aircraft_roles.no_user_with_that")
    end
    role = @aircraft.roles.new(user: user, role: params[:role])
    if role.save
      log_event("role", t("flash.aircraft_roles.added_as", display_name: user.display_name, role: role.role))
      redirect_to aircraft_aircraft_roles_path(@aircraft), notice: t("flash.aircraft_roles.added", display_name: user.display_name)
    else
      redirect_to aircraft_aircraft_roles_path(@aircraft), alert: role.errors.full_messages.to_sentence
    end
  end

  def update
    role = @aircraft.roles.find(params[:id])
    if demoting_last_owner?(role, params[:role])
      return redirect_to aircraft_aircraft_roles_path(@aircraft), alert: t("flash.aircraft_roles.an_aircraft_must_keep")
    end
    role.update!(role: params[:role])
    log_event("role", t("flash.aircraft_roles.changed_to", display_name: role.user.display_name, role: role.role))
    redirect_to aircraft_aircraft_roles_path(@aircraft), notice: t("flash.aircraft_roles.role_updated")
  end

  def destroy
    role = @aircraft.roles.find(params[:id])
    if role.user == current_user
      return redirect_to aircraft_aircraft_roles_path(@aircraft), alert: t("flash.aircraft_roles.you_can_t_remove")
    end
    if demoting_last_owner?(role, nil)
      return redirect_to aircraft_aircraft_roles_path(@aircraft), alert: t("flash.aircraft_roles.an_aircraft_must_keep_2")
    end
    role.destroy!
    log_event("role", t("flash.aircraft_roles.removed", display_name: role.user.display_name))
    redirect_to aircraft_aircraft_roles_path(@aircraft), notice: t("flash.aircraft_roles.access_removed")
  end

  private

  def demoting_last_owner?(role, new_role)
    role.role == "owner" && new_role != "owner" && @aircraft.roles.owners.count <= 1
  end
end

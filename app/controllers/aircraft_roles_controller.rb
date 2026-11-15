# Who can access the aircraft, with which role ("manage people"), and its
# public share links ("manage sharing", see ShareTokensController). The rules
# for changing roles are in AircraftAccess.
class AircraftRolesController < ApplicationController
  include AircraftScoped
  checks_permission_itself only: :index
  requires_permission :manage_people, only: %i[create update destroy]

  def index
    return permission_denied unless can?(:manage_people) || can?(:manage_sharing) || can?(:export_data)
    @access = AircraftAccess.new(@aircraft, actor: current_user)
    @roles = @aircraft.roles.includes(:user, :role).joins(:role).order("roles.position", :created_at)
    @share_tokens = @aircraft.share_tokens.order(created_at: :desc).includes(:created_by)
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    return back(alert: t("flash.aircraft_roles.no_user_with_that")) unless user
    error = access.add(user, Role.find_by(id: params[:role_id]))
    back(error ? { alert: error } : { notice: t("flash.aircraft_roles.added", display_name: user.display_name) })
  end

  def update
    error = access.change(@aircraft.roles.find(params[:id]), Role.find_by(id: params[:role_id]))
    back(error ? { alert: error } : { notice: t("flash.aircraft_roles.role_updated") })
  end

  def destroy
    error = access.remove(@aircraft.roles.find(params[:id]))
    back(error ? { alert: error } : { notice: t("flash.aircraft_roles.access_removed") })
  end

  private

  def access = AircraftAccess.new(@aircraft, actor: current_user)
  def back(flash) = redirect_to(aircraft_aircraft_roles_path(@aircraft), flash)
end

# Administrators give people roles on any aircraft (from Admin → Users),
# under the same rules as the aircraft's Access page (AircraftAccess).
class Admin::UserAircraftRolesController < ApplicationController
  before_action :require_admin!
  before_action :set_user

  def create
    aircraft = Aircraft.find_by(id: params[:aircraft_id])
    return back(alert: t("services.aircraft_access.not_found")) unless aircraft
    back_with AircraftAccess.new(aircraft, actor: current_user).add(@user, Role.find_by(id: params[:role_id])),
              t("flash.admin_users.access_added", tail_number: aircraft.tail_number)
  end

  def update
    membership = @user.aircraft_roles.find(params[:id])
    back_with AircraftAccess.new(membership.aircraft, actor: current_user).change(membership, Role.find_by(id: params[:role_id])),
              t("flash.admin_users.access_changed", tail_number: membership.aircraft.tail_number)
  end

  def destroy
    membership = @user.aircraft_roles.find(params[:id])
    back_with AircraftAccess.new(membership.aircraft, actor: current_user).remove(membership),
              t("flash.admin_users.access_removed", tail_number: membership.aircraft.tail_number)
  end

  private

  def set_user = @user = User.find(params[:user_id])
  def back(flash) = redirect_to(edit_admin_user_path(@user, anchor: "access"), flash)
  def back_with(error, notice) = back(error ? { alert: error } : { notice: notice })
end

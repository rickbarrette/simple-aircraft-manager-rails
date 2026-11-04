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
                         alert: "No user with that email. Ask an administrator to create their account first."
    end
    role = @aircraft.roles.new(user: user, role: params[:role])
    if role.save
      log_event("role", "#{user.display_name} added as #{role.role}")
      redirect_to aircraft_aircraft_roles_path(@aircraft), notice: "#{user.display_name} added."
    else
      redirect_to aircraft_aircraft_roles_path(@aircraft), alert: role.errors.full_messages.to_sentence
    end
  end

  def update
    role = @aircraft.roles.find(params[:id])
    if demoting_last_owner?(role, params[:role])
      return redirect_to aircraft_aircraft_roles_path(@aircraft), alert: "An aircraft must keep at least one owner."
    end
    role.update!(role: params[:role])
    log_event("role", "#{role.user.display_name} changed to #{role.role}")
    redirect_to aircraft_aircraft_roles_path(@aircraft), notice: "Role updated."
  end

  def destroy
    role = @aircraft.roles.find(params[:id])
    if role.user == current_user
      return redirect_to aircraft_aircraft_roles_path(@aircraft), alert: "You can't remove yourself."
    end
    if demoting_last_owner?(role, nil)
      return redirect_to aircraft_aircraft_roles_path(@aircraft), alert: "An aircraft must keep at least one owner."
    end
    role.destroy!
    log_event("role", "#{role.user.display_name} removed")
    redirect_to aircraft_aircraft_roles_path(@aircraft), notice: "Access removed."
  end

  private

  def demoting_last_owner?(role, new_role)
    role.role == "owner" && new_role != "owner" && @aircraft.roles.owners.count <= 1
  end
end

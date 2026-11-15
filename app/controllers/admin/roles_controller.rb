# The roles people can have on an aircraft and what each allows (Role,
# Permission). Owner always has every permission; the other built-in roles
# can be changed but not deleted; administrators can add their own.
class Admin::RolesController < ApplicationController
  before_action :require_admin!
  before_action :set_role, only: %i[edit update destroy]

  def index
    Role.ensure_built_in!
    @roles = Role.ordered
    @counts = AircraftRole.group(:role_id).count
  end

  def new
    @role = Role.new(permissions: Permission::DEFAULTS["viewer"])
  end

  def create
    @role = Role.new(role_params)
    if @role.save
      redirect_to admin_roles_path, notice: t("flash.admin_roles.created", name: @role.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attributes = @role.owner? ? role_params.except(:permissions) : role_params
    if @role.update(attributes)
      redirect_to admin_roles_path, notice: t("flash.admin_roles.updated", name: @role.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @role.built_in?
      redirect_to admin_roles_path, alert: t("flash.admin_roles.built_in")
    elsif @role.aircraft_roles.exists?
      redirect_to admin_roles_path, alert: t("flash.admin_roles.in_use", name: @role.name, count: @role.aircraft_roles.count)
    else
      @role.destroy!
      redirect_to admin_roles_path, notice: t("flash.admin_roles.deleted", name: @role.name)
    end
  end

  private

  def set_role = @role = Role.find(params[:id])

  # Unticking every box sends none, so an empty list is always sent too.
  def role_params
    params.require(:role).permit(:name, :description, permissions: []).tap { _1[:permissions] = Array(_1[:permissions]).compact_blank }
  end
end

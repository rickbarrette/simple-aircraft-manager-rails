# Scopes a controller to one aircraft the current user can access, and checks
# what their role there allows (Role, Permission). Unknown and inaccessible
# aircraft both 404 (enumeration-safe). Administrators can do everything.
#
# Each controller says which permission its actions need:
#
#   requires_permission :manage_components, except: %i[index show]
#   requires_permission :report_squawks, only: %i[new create]
#   checks_permission_itself only: %i[edit update]   # decided in the controller
#
# Looking needs no permission. A request that changes something (anything but
# GET/HEAD) with no permission declared for its action is refused, so nothing
# is left open by mistake; in development and tests it raises instead.
module AircraftScoped
  extend ActiveSupport::Concern

  SELF_CHECKED = "(checked by the controller)".freeze

  class MissingPermission < StandardError; end

  included do
    class_attribute :permission_rules, instance_accessor: false, default: []
    before_action :set_aircraft
    before_action :authorize_permission!
    helper_method :current_role, :can?, :owner?
  end

  class_methods do
    def requires_permission(permission, only: nil, except: nil)
      self.permission_rules += [ [ permission.to_s, only && Array(only).map(&:to_s), except && Array(except).map(&:to_s) ] ]
    end

    def checks_permission_itself(only:)
      requires_permission(SELF_CHECKED, only: only)
    end
  end

  private

  def aircraft_param = params[:aircraft_id]

  def set_aircraft
    @aircraft = current_user.accessible_aircraft.find(aircraft_param)
  end

  # Their Role here (nil for an administrator without one).
  def current_role
    return @current_role if defined?(@current_role)
    @current_role = current_user.role_for(@aircraft)
  end

  def can?(permission) = current_user.admin? || current_role&.can?(permission) || false

  # The Owner role (or an administrator): everything.
  def owner? = current_user.admin? || current_role&.owner? || false

  def authorize_permission!
    rules = self.class.permission_rules.select do |_, only, except|
      (only.nil? || only.include?(action_name)) && (except.nil? || except.exclude?(action_name))
    end
    if rules.empty?
      return if request.get? || request.head?
      raise MissingPermission, "#{self.class.name}##{action_name} changes data without declaring a permission" if Rails.env.local?
      return permission_denied
    end
    permission_denied unless rules.all? { |permission, *| permission == SELF_CHECKED || can?(permission) }
  end

  def permission_denied
    respond_to do |format|
      format.html { redirect_back fallback_location: aircraft_path(@aircraft), alert: t("flash.common.not_allowed") }
      format.any { head :forbidden }
    end
  end

  # Returns id only if it belongs to the given (aircraft-scoped) relation; else nil.
  def scoped_id(scope, id)
    id.present? && scope.where(id: id).exists? ? id : nil
  end

  def log_event(category, name, notes: nil)
    @aircraft.log_event!(category, name, notes: notes)
  end
end

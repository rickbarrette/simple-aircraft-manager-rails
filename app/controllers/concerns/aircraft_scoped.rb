# Scopes a controller to one aircraft the current user can access and exposes
# role helpers. Unknown and inaccessible aircraft both 404 (enumeration-safe).
#
# Access matrix (mirrors the original):
#   admin  – everything
#   owner  – everything on their aircraft
#   pilot  – view all; update hours; create squawks, notes, oil/fuel, flight logs
module AircraftScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_aircraft
    helper_method :current_role, :owner?, :can_write?
  end

  private

  def aircraft_param = params[:aircraft_id]

  def set_aircraft
    @aircraft = current_user.accessible_aircraft.find(aircraft_param)
  end

  def current_role
    @current_role ||= current_user.role_for(@aircraft)
  end

  # Owner-level write access (admins included).
  def owner? = current_role.in?(%w[admin owner])
  alias_method :can_write?, :owner?

  def require_owner!
    return if owner?
    redirect_back fallback_location: aircraft_path(@aircraft),
                  alert: "Only owners can do that."
  end

  # Returns id only if it belongs to the given (aircraft-scoped) relation; else nil.
  def scoped_id(scope, id)
    id.present? && scope.where(id: id).exists? ? id : nil
  end

  def log_event(category, name, notes: nil)
    @aircraft.log_event!(category, name, notes: notes)
  end
end

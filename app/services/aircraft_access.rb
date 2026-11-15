# Giving, changing and taking away people's roles on an aircraft, by someone
# allowed to (the aircraft's "manage people", or an administrator). The rules,
# the same from the aircraft's Access page and Admin → Users:
# - only an Owner or an administrator can give or take away the Owner role
#   (otherwise anyone who manages people could make themselves Owner);
# - only an administrator can change or remove their own role;
# - an aircraft always keeps at least one Owner.
# Each method returns nil when done, or a message saying why not.
class AircraftAccess
  def initialize(aircraft, actor:)
    @aircraft = aircraft
    @actor = actor
  end

  def add(user, role)
    return t("not_found") unless user && role
    return t("owner_only") if role.owner? && !actor_owner?
    membership = @aircraft.roles.new(user: user, role: role)
    return membership.errors.full_messages.to_sentence unless membership.save
    @aircraft.log_event!("role", I18n.t("flash.aircraft_roles.added_as", display_name: user.display_name, role: role.name), user: @actor)
    nil
  end

  def change(membership, role)
    return t("not_found") unless role
    return if membership.role == role
    return t("own_role") if membership.user == @actor && !@actor.admin?
    return t("owner_only") if (role.owner? || membership.owner?) && !actor_owner?
    return t("last_owner") if membership.owner? && !role.owner? && last_owner?
    membership.update!(role: role)
    @aircraft.log_event!("role", I18n.t("flash.aircraft_roles.changed_to", display_name: membership.user.display_name, role: role.name), user: @actor)
    nil
  end

  def remove(membership)
    return t("own_role") if membership.user == @actor && !@actor.admin?
    return t("owner_only") if membership.owner? && !actor_owner?
    return t("last_owner") if membership.owner? && last_owner?
    membership.destroy!
    @aircraft.log_event!("role", I18n.t("flash.aircraft_roles.removed", display_name: membership.user.display_name), user: @actor)
    nil
  end

  # The roles this person can hand out here (Owner only by an Owner).
  def assignable_roles = Role.ordered.select { |role| !role.owner? || actor_owner? }

  private

  def actor_owner? = @actor.admin? || @actor.role_for(@aircraft)&.owner?
  def last_owner? = @aircraft.roles.owners.count <= 1
  def t(key) = I18n.t("services.aircraft_access.#{key}")
end

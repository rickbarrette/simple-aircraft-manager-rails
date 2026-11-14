# Flight-activity writes: absolute hours updates and flight logs. Both cascade
# the time-in-service delta (tach or Hobbs, per the aircraft's maintenance
# clock) to every IN-USE component.
class HoursService
  H = "services.hours_service"
  def initialize(aircraft, user: Current.user)
    @aircraft = aircraft
    @user = user
  end

  def enforce_airworthiness!
    return unless @aircraft.airworthiness_enforcement?
    status = Airworthiness.new(@aircraft).call
    raise AircraftGroundedError, status if status.red?
  end

  # Set absolute tach (and optional hobbs); component hours are clamped at 0
  # so downward corrections can't go negative.
  def update_hours!(tach_time:, hobbs_time: nil)
    enforce_airworthiness!
    tach = BigDecimal(tach_time.to_s)
    hobbs = BigDecimal(hobbs_time.to_s) if hobbs_time.present?
    old = @aircraft.tach_time
    tach_delta = tach - old
    # On Hobbs time, components follow the Hobbs change (when one is given).
    delta = @aircraft.hobbs? && hobbs ? hobbs - @aircraft.hobbs_time : tach_delta

    Aircraft.transaction do
      @aircraft.tach_time = tach
      @aircraft.hobbs_time = hobbs if hobbs
      @aircraft.save!
      cascade_to_components(delta, clamp: true)
      @aircraft.log_event!("hours",
        I18n.t(tach_delta >= 0 ? "#{H}.hours_updated" : "#{H}.hours_corrected", tach: tach),
        user: @user, notes: I18n.t("#{H}.hours_notes", old: old, delta: "#{'+' if tach_delta >= 0}#{tach_delta}"))
    end
    tach_delta
  end

  # Persist a flight log and apply its side effects atomically.
  def log_flight!(flight)
    enforce_airworthiness!
    Aircraft.transaction do
      flight.aircraft = @aircraft
      flight.user ||= @user
      flight.save!

      @aircraft.tach_time += flight.tach_time
      @aircraft.hobbs_time += flight.hobbs_time if flight.hobbs_time
      @aircraft.save!
      cascade_to_components(@aircraft.hobbs? && flight.hobbs_time ? flight.hobbs_time : flight.tach_time)

      { "oil" => [ flight.oil_added, flight.oil_level_after, flight.oil_added_type ],
        "fuel" => [ flight.fuel_added, flight.fuel_level_after, flight.fuel_added_type ] }.each do |type, (qty, level, kind)|
        next unless qty.to_f > 0
        @aircraft.consumable_records.create!(
          record_type: type, flight_log: flight, date: flight.date, quantity_added: qty,
          level_after: level, consumable_type: kind, flight_hours: @aircraft.tach_time,
          notes: I18n.t("services.hours_service.auto_created_from_flight_log"))
        @aircraft.log_event!(type, I18n.t("#{H}.consumable_added", type: ConsumableRecord::TYPES[type], quantity: qty, unit: ConsumableRecord::UNITS[type]),
                             user: @user, notes: I18n.t("services.hours_service.from_flight_log"))
      end

      route = flight.route_summary.presence
      @aircraft.log_event!("flight", I18n.t(route ? "#{H}.flight_logged_route" : "#{H}.flight_logged", hours: flight.tach_time, route: route), user: @user)
    end
    flight
  end

  private

  def cascade_to_components(delta, clamp: false)
    @aircraft.components.in_use.find_each do |c|
      his = c.hours_in_service + delta
      hso = c.hours_since_overhaul + delta
      his, hso = [ his, 0 ].max, [ hso, 0 ].max if clamp
      c.update_columns(hours_in_service: his, hours_since_overhaul: hso, updated_at: Time.current)
    end
  end
end

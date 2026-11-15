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

  # Correct a saved flight. Its readings change only when it's the latest
  # (FlightLog#meters_editable?); the aircraft and its components then move by
  # the difference. Its oil and fuel records follow. With both readings given,
  # the duration is worked out from them.
  def update_flight!(flight, attributes)
    Aircraft.transaction do
      before = flight.attributes.slice(*FlightLog::METERS, "date", "departure_location", "destination_location",
                                       "oil_added", "fuel_added", "route", "notes")
      flight.assign_attributes(attributes)
      flight.tach_time = flight.tach_in - flight.tach_out if flight.tach_in && flight.tach_out
      flight.hobbs_time = flight.hobbs_in - flight.hobbs_out if flight.hobbs_in && flight.hobbs_out
      flight.save!

      tach_delta = flight.tach_time - before["tach_time"].to_d
      hobbs_delta = flight.hobbs_time.to_d - before["hobbs_time"].to_d
      if tach_delta.nonzero? || hobbs_delta.nonzero?
        @aircraft.tach_time += tach_delta
        @aircraft.hobbs_time += hobbs_delta if @aircraft.hobbs_time
        @aircraft.save!
        cascade_to_components(@aircraft.hobbs? && flight.hobbs_time ? hobbs_delta : tach_delta, clamp: true)
      end
      sync_consumables(flight)

      changed = before.keys.reject { |key| before[key] == flight[key] }
      @aircraft.log_event!("flight", I18n.t("#{H}.flight_corrected", date: I18n.l(flight.date, format: :app)), user: @user,
                           notes: changed.map { |key| FlightLog.human_attribute_name(key) }.join(", ").presence)
    end
    flight
  end

  private

  # The flight's oil and fuel records match what it says was added.
  def sync_consumables(flight)
    { "oil" => [ flight.oil_added, flight.oil_level_after, flight.oil_added_type ],
      "fuel" => [ flight.fuel_added, flight.fuel_level_after, flight.fuel_added_type ] }.each do |type, (qty, level, kind)|
      record = flight.consumable_records.find_by(record_type: type)
      if qty.to_f.positive?
        record ||= @aircraft.consumable_records.new(record_type: type, flight_log: flight, flight_hours: @aircraft.tach_time,
                                                     notes: I18n.t("#{H}.auto_created_from_flight_log"))
        record.update!(date: flight.date, quantity_added: qty, level_after: level, consumable_type: kind)
      else
        record&.destroy!
      end
    end
  end

  def cascade_to_components(delta, clamp: false)
    @aircraft.components.in_use.find_each do |c|
      his = c.hours_in_service + delta
      hso = c.hours_since_overhaul + delta
      his, hso = [ his, 0 ].max, [ hso, 0 ].max if clamp
      c.update_columns(hours_in_service: his, hours_since_overhaul: hso, updated_at: Time.current)
    end
  end
end

# One day of flying on the Flights tab: its legs in the order flown, the
# route as one chain (KOQU → KBID → KOQU), and the day's totals.
class FlightDay
  attr_reader :date, :flights

  def self.group(flight_logs)
    flight_logs.group_by(&:date).map { |date, flights| new(date, flights) }.sort_by(&:date).reverse
  end

  def initialize(date, flights)
    @date = date
    # Order flown: by tach out where known, then by when they were logged.
    @flights = flights.sort_by { [ _1.tach_out || 0, _1.created_at || Time.at(0) ] }
  end

  # The day's airports chained leg to leg; a gap (a leg that doesn't start
  # where the last one ended, or a missing code) starts a new chain: "A → B · C → D".
  def route
    chains = []
    current = []
    flights.each do |f|
      from = f.departure_location.presence
      to = f.destination_location.presence
      if from && current.any? && from != current.last
        chains << current
        current = []
      end
      current << from if from && current.empty?
      current << to if to
    end
    chains << current if current.any?
    chains.map { _1.join(" → ") }.join(" · ")
  end

  def tach_time = sum(:tach_time)
  def hobbs_time = sum(:hobbs_time)
  def fuel_added = sum(:fuel_added)
  def oil_added = sum(:oil_added)
  def pilots = flights.filter_map { _1.user&.display_name }.uniq
  def track_log? = flights.any? { _1.track_log.attached? }
  def engine_data? = flights.any? { _1.engine_data.attached? }

  private

  # nil when no leg recorded it, so "—" can be shown instead of 0.
  def sum(attr)
    values = flights.filter_map(&attr)
    values.sum if values.any?
  end
end

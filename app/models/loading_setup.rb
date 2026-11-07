# Loading stations (name, arm, maximum, fuel or not) and the CG envelope
# (weight/CG points in order around the boundary), as entered from the POH.
class LoadingSetup
  include ActiveModel::Model

  Station = Data.define(:name, :arm, :max, :fuel)

  attr_accessor :stations, :envelope, :fuel_lb_per_gal

  def self.from_aircraft(aircraft)
    data = aircraft.loading_stations.is_a?(Hash) ? aircraft.loading_stations : {}
    new(stations: Array(data["stations"]).map { Station.new(name: _1["name"], arm: _1["arm"].to_d, max: _1["max"]&.to_d, fuel: _1["fuel"] == true) },
        envelope: Array(aircraft.cg_envelope).map { [ _1[0].to_d, _1[1].to_d ] },
        fuel_lb_per_gal: (data["fuel_lb_per_gal"] || 6).to_d)
  end

  # From the edit form: blank rows are ignored.
  def self.from_params(p)
    rows = Array(p["stations"]&.values).reject { _1["name"].to_s.strip.empty? && _1["arm"].to_s.strip.empty? }
    points = Array(p["envelope"]&.values).reject { _1["weight"].to_s.strip.empty? && _1["cg"].to_s.strip.empty? }
    setup = new(fuel_lb_per_gal: p["fuel_lb_per_gal"].presence&.to_d || 6, stations: [], envelope: [])
    setup.instance_variable_set(:@raw_stations, rows)
    setup.instance_variable_set(:@raw_envelope, points)
    setup.stations = rows.filter_map do |r|
      next unless numeric?(r["arm"])
      Station.new(name: r["name"].to_s.strip.first(40), arm: r["arm"].to_d, max: numeric?(r["max"]) ? r["max"].to_d : nil, fuel: r["fuel"] == "1")
    end
    setup.envelope = points.filter_map { numeric?(_1["weight"]) && numeric?(_1["cg"]) ? [ _1["weight"].to_d, _1["cg"].to_d ] : nil }
    setup
  end

  def self.numeric?(v) = v.to_s.strip.match?(/\A-?\d+(\.\d+)?\z/)

  validate do
    raw_s = @raw_stations || []
    raw_e = @raw_envelope || []
    errors.add(:base, "Every station needs a name and a numeric arm (inches)") if raw_s.size != stations.size || stations.any? { _1.name.blank? }
    errors.add(:base, "Every envelope point needs a numeric weight and CG") if raw_e.size != envelope.size
    errors.add(:base, "The CG envelope needs at least 3 points, or none") if envelope.size.between?(1, 2)
    errors.add(:base, "Fuel weight per gallon must be between 4 and 9 lb") unless fuel_lb_per_gal.to_d.between?(4, 9)
  end

  def stations_json
    { "fuel_lb_per_gal" => fuel_lb_per_gal.to_f,
      "stations" => stations.map { { "name" => _1.name, "arm" => _1.arm.to_f, "max" => _1.max&.to_f, "fuel" => _1.fuel } } }
  end

  def configured? = stations.any?
end

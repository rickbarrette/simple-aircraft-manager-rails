# Loading stations (name, arm, maximum, fuel or not) and the CG envelope
# (weight/CG points in order around the boundary), as entered from the POH.
# The envelope is stored as CG in inches; it can be entered as moment in
# lb-in/1000 (how many POH charts and Garmin Pilot give it) and is shown
# back the way it was entered.
class LoadingSetup
  include ActiveModel::Model

  Station = Data.define(:name, :arm, :max, :fuel)

  ENVELOPE_UNITS = LabelSet.new("loading_setup.envelope_units", %w[cg moment])

  attr_accessor :stations, :envelope, :fuel_lb_per_gal
  attr_writer :envelope_unit

  def envelope_unit = ENVELOPE_UNITS.key?(@envelope_unit) ? @envelope_unit : "cg"
  def moment? = envelope_unit == "moment"

  # The envelope as entered: [weight, CG in] or [weight, moment / 1000].
  def entered_envelope
    return envelope unless moment?
    envelope.map { |w, cg| [ w, (w * cg / 1000).round(3) ] }
  end

  def self.from_aircraft(aircraft)
    data = aircraft.loading_stations.is_a?(Hash) ? aircraft.loading_stations : {}
    new(stations: Array(data["stations"]).map { Station.new(name: _1["name"], arm: _1["arm"].to_d, max: _1["max"]&.to_d, fuel: _1["fuel"] == true) },
        envelope: Array(aircraft.cg_envelope).map { [ _1[0].to_d, _1[1].to_d ] },
        fuel_lb_per_gal: (data["fuel_lb_per_gal"] || 6).to_d, envelope_unit: data["envelope_unit"])
  end

  # From the edit form: blank rows are ignored.
  def self.from_params(p)
    rows = Array(p["stations"]&.values).reject { _1["name"].to_s.strip.empty? && _1["arm"].to_s.strip.empty? }
    points = Array(p["envelope"]&.values).reject { _1["weight"].to_s.strip.empty? && _1["cg"].to_s.strip.empty? }
    setup = new(fuel_lb_per_gal: p["fuel_lb_per_gal"].presence&.to_d || 6, stations: [], envelope: [], envelope_unit: p["envelope_unit"])
    setup.instance_variable_set(:@raw_stations, rows)
    setup.instance_variable_set(:@raw_envelope, points)
    setup.stations = rows.filter_map do |r|
      next unless numeric?(r["arm"])
      Station.new(name: r["name"].to_s.strip.first(40), arm: r["arm"].to_d, max: numeric?(r["max"]) ? r["max"].to_d : nil, fuel: r["fuel"] == "1")
    end
    setup.envelope = points.filter_map do |pt|
      next unless numeric?(pt["weight"]) && numeric?(pt["cg"])
      weight = pt["weight"].to_d
      value = pt["cg"].to_d
      next [ weight, value ] unless setup.moment?
      [ weight, weight.positive? ? (value * 1000 / weight).round(4) : value ]
    end
    setup
  end

  def self.numeric?(v) = v.to_s.strip.match?(/\A-?\d+(\.\d+)?\z/)

  validate do
    raw_s = @raw_stations || []
    raw_e = @raw_envelope || []
    errors.add(:base, :stations) if raw_s.size != stations.size || stations.any? { _1.name.blank? }
    errors.add(:base, :envelope_points) if raw_e.size != envelope.size
    errors.add(:base, :envelope_size) if envelope.size.between?(1, 2)
    errors.add(:base, :envelope_weights) if envelope.any? { |w, _| !w.positive? }
    errors.add(:base, :fuel_weight) unless fuel_lb_per_gal.to_d.between?(4, 9)
  end

  def stations_json
    { "fuel_lb_per_gal" => fuel_lb_per_gal.to_f, "envelope_unit" => envelope_unit,
      "stations" => stations.map { { "name" => _1.name, "arm" => _1.arm.to_f, "max" => _1.max&.to_f, "fuel" => _1.fuel } } }
  end

  def configured? = stations.any?
end

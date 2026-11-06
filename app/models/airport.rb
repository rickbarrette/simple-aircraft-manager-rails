# Airport reference data from OurAirports (the source AirTrail uses).
# Loaded by AirportData; refresh with `bin/rails airports:refresh`.
class Airport < ApplicationRecord
  KINDS = %w[small_airport medium_airport large_airport seaplane_base heliport balloonport closed].freeze
  KIND_RANK = { "large_airport" => 0, "medium_airport" => 1, "small_airport" => 2, "seaplane_base" => 3,
                "heliport" => 4, "balloonport" => 5, "closed" => 9 }.freeze
  KIND_LABELS = { "seaplane_base" => "seaplane base", "heliport" => "heliport", "balloonport" => "balloonport", "closed" => "closed" }.freeze

  # Custom airports (admin-added) use their identifier as the AirTrail code.
  before_validation(if: :custom?) { self.airtrail_code = ident }
  normalizes :ident, :gps_code, :local_code, :iata, with: ->(c) { c.strip.upcase.presence }

  validates :ident, presence: true, uniqueness: true, length: { maximum: 10 }
  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }, allow_blank: true
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  scope :custom, -> { where(custom: true) }

  # The standard code for logging: AirTrail's (ICAO-style, e.g. K1B9 for FAA
  # 1B9), so logged codes, the airport database and AirTrail all agree.
  def code = airtrail_code

  # Other codes the airport goes by (FAA/local, GPS, IATA), e.g. ["1B9"].
  def other_codes = [ local_code, gps_code, iata ].compact.uniq - [ code ]

  def place = [ municipality, region.to_s.split("-", 2).last.presence ].compact.join(", ")

  def as_suggestion
    { code: code, name: name, place: place, airtrail_code: airtrail_code, kind: KIND_LABELS[kind], aka: other_codes }
  end

  # Best match for a code someone logged, whichever code system it's in.
  def self.lookup(code)
    c = code.to_s.strip.upcase
    return nil if c.empty?
    candidates = where(ident: c).or(where(gps_code: c)).or(where(local_code: c)).or(where(airtrail_code: c)).or(where(iata: c)).to_a
    candidates.min_by do |a|
      field = [ a.ident, a.gps_code, a.local_code, a.airtrail_code, a.iata ].index(c) || 9
      [ a.kind == "closed" ? 1 : 0, field, KIND_RANK.fetch(a.kind, 8) ]
    end
  end

  # The code AirTrail uses for the airport someone logged, or nil if unknown.
  def self.airtrail_code_for(code) = lookup(code)&.airtrail_code

  # Autocomplete: exact codes, then code prefixes, then name/town matches.
  # `prefer`: codes to rank first (e.g. airports this aircraft has used).
  def self.search(query, limit: 10, prefer: [])
    q = query.to_s.strip
    return [] if q.length < 2
    up = q.upcase
    like_prefix = "#{sanitize_sql_like(up)}%"
    like_any = "%#{sanitize_sql_like(q)}%"
    exact = where(ident: up).or(where(airtrail_code: up)).or(where(gps_code: up)).or(where(local_code: up)).or(where(iata: up)).to_a
    prefix = up.match?(/\A[A-Z0-9]{1,4}\z/) ? where("gps_code LIKE :p OR local_code LIKE :p OR ident LIKE :p", p: like_prefix).limit(200).to_a : []
    named = where("name LIKE :q OR municipality LIKE :q", q: like_any).limit(400).to_a
    preferred = prefer.to_set { _1.to_s.upcase }
    familiar = ->(a) { [ a.code, a.ident, a.gps_code, a.local_code ].any? { preferred.include?(_1) } ? 0 : 1 }
    rank = ->(a) { [ familiar.(a), a.kind == "closed" ? 1 : 0, KIND_RANK.fetch(a.kind, 8), a.code.length, a.code ] }
    (exact.sort_by(&rank) + prefix.sort_by(&rank) + named.sort_by(&rank)).uniq(&:id).first(limit)
  end
end

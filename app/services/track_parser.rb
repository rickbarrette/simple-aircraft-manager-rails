require "csv"

# Parses a flight's GPS track log (GPX, KML or CSV) into AirTrail's track
# format: coordinates as [lon, lat, altitude_m] plus aligned epoch-second
# times. Mirrors AirTrail's own parser (src/lib/track/parser.ts):
#   GPX: <trkpt>/<rtept> lat/lon attributes, <ele> in meters, <time>
#   KML: <LineString><coordinates> "lon,lat,alt" and <gx:Track> <when>/<gx:coord>
#   CSV: latitude/longitude/altitude/time columns, altitude in FEET
class TrackParser
  class Error < StandardError; end

  MAX_POINTS = 100_000 # AirTrail's stored-track limit
  FEET_TO_M = 0.3048
  LAT_HEADERS = %w[latitude lat].freeze
  LON_HEADERS = %w[longitude lon lng long].freeze
  ALT_HEADERS = %w[altitude alt altitude_ft altitude_feet altitudeft altitudefeet].freeze
  TIME_HEADERS = %w[timestamp time date_time datetime utc_time].freeze

  Track = Struct.new(:coordinates, :times, :source_format, :source_name, keyword_init: true) do
    def points = coordinates.size
    def max_altitude_ft = (alts = coordinates.filter_map { _1[2] }).any? ? (alts.max / FEET_TO_M).round : nil

    # AirTrail TrackInput
    def as_air_trail_json
      { coordinates: coordinates, sourceFormat: source_format, sourceName: source_name.to_s.first(255).presence }
        .tap { |h| h[:times] = times if times }
    end
  end

  def self.parse_attachment(attachment)
    return nil unless attachment&.attached?
    attachment.blob.open { |file| new(file.read, filename: attachment.filename.to_s).parse }
  end

  def initialize(content, filename:)
    @content = content.to_s
    @filename = filename.to_s
  end

  def parse
    coords, times =
      case format
      when "gpx" then parse_gpx
      when "kml" then parse_kml
      when "csv" then parse_csv
      else raise Error, "Unsupported track format"
      end
    raise Error, "Track has fewer than 2 points" if coords.size < 2
    times = nil unless times && times.size == coords.size
    coords, times = downsample(coords, times)
    Track.new(coordinates: coords, times: times, source_format: format, source_name: @filename)
  end

  def format
    @format ||= case File.extname(@filename).downcase
    when ".gpx" then "gpx"
    when ".kml" then "kml"
    when ".csv" then "csv"
    else
      head = @content[0, 2000]
      if head.include?("<gpx") then "gpx"
      elsif head.include?("<kml") then "kml"
      elsif head.match?(/lat/i) && head.include?(",") then "csv"
      end
    end
  end

  private

  def xml
    Nokogiri::XML(@content) { |config| config.nonet }.tap(&:remove_namespaces!)
  end

  def parse_gpx
    coords = []
    times = []
    xml.xpath("//trkpt | //rtept").each do |pt|
      lat = number(pt["lat"])
      lon = number(pt["lon"])
      next unless valid?(lat, lon)
      alt = number(pt.at_xpath("ele")&.text)
      coords << coordinate(lon, lat, alt)
      times << epoch(pt.at_xpath("time")&.text)
    end
    [ coords, times.all? ? times : nil ]
  end

  def parse_kml
    doc = xml
    track_points = doc.xpath("//Track")
    if track_points.any?
      coords = []
      times = []
      track_points.each do |track|
        whens = track.xpath("when").map(&:text)
        track.xpath("coord").each_with_index do |c, i|
          lon, lat, alt = c.text.split.map { number(_1) }
          next unless valid?(lat, lon)
          coords << coordinate(lon, lat, alt)
          times << epoch(whens[i])
        end
      end
      return [ coords, times.all? ? times : nil ]
    end

    coords = doc.xpath("//LineString/coordinates").flat_map do |node|
      node.text.split.filter_map do |triple|
        lon, lat, alt = triple.split(",").map { number(_1) }
        coordinate(lon, lat, alt) if valid?(lat, lon)
      end
    end
    [ coords, nil ]
  end

  def parse_csv
    rows = CSV.parse(@content.sub(/\A﻿/, ""), headers: true)
    headers = rows.headers.compact
    find = ->(names) { headers.find { |h| names.include?(h.to_s.strip.downcase.gsub(/[^a-z_]/, "")) } }
    lat_h, lon_h, alt_h, time_h = find.(LAT_HEADERS), find.(LON_HEADERS), find.(ALT_HEADERS), find.(TIME_HEADERS)
    raise Error, "CSV track needs latitude and longitude columns" unless lat_h && lon_h

    coords = []
    times = []
    rows.each do |row|
      lat = number(row[lat_h])
      lon = number(row[lon_h])
      next unless valid?(lat, lon)
      alt_ft = alt_h && number(row[alt_h])
      coords << coordinate(lon, lat, alt_ft && alt_ft * FEET_TO_M)
      times << (time_h && epoch(row[time_h]))
    end
    [ coords, times.all? ? times : nil ]
  rescue CSV::MalformedCSVError => e
    raise Error, "Couldn't read CSV track (#{e.message})"
  end

  def coordinate(lon, lat, alt)
    alt ? [ lon.round(6), lat.round(6), alt.round(1) ] : [ lon.round(6), lat.round(6) ]
  end

  def valid?(lat, lon) = lat && lon && lat.between?(-90, 90) && lon.between?(-180, 180)

  def number(value)
    Float(value.to_s.strip)
  rescue ArgumentError, TypeError
    nil
  end

  # ISO 8601 or epoch seconds/milliseconds → epoch seconds.
  def epoch(value)
    v = value.to_s.strip
    return nil if v.empty?
    if v.match?(/\A-?\d+(\.\d+)?\z/)
      n = v.to_f
      return (n > 10_000_000_000 ? n / 1000 : n).round
    end
    Time.iso8601(v).to_i
  rescue ArgumentError
    Time.parse(v).to_i rescue nil
  end

  def downsample(coords, times)
    return [ coords, times ] if coords.size <= MAX_POINTS
    step = (coords.size.to_f / MAX_POINTS).ceil
    keep = (0...coords.size).step(step).to_a
    keep << coords.size - 1 unless keep.last == coords.size - 1
    [ keep.map { coords[_1] }, times && keep.map { times[_1] } ]
  end
end

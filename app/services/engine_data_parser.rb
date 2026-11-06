# Parses an engine monitor's flight data recording into time series plus a
# summary (run time, hours, fuel burned, peak temperatures).
#
# Supported: Electronics International CGR-30P / CGR-30C CSV recordings —
#   a metadata block ("Aircraft ID....: N12345", "Local Time: 2025/07/14 08:11:45",
#   "Zulu Time.: …"), then a header row "TIME,SEL TANK QTY,RPMLEFT;RPM,…,EGT1;*F,…"
#   (name;unit) and one row per sample stamped with local HH:MM:SS, several per
#   second. A recording cut off mid-write leaves a partial row; those are skipped.
class EngineDataParser
  class Error < StandardError; end

  RUNNING_RPM = 300      # below this the engine is off (or starting)
  MAX_GAP_SECONDS = 10   # don't integrate fuel flow across a hole in the data
  CHART_POINTS = 600
  DETAIL_POINTS = 6000   # the interactive chart viewer's resolution
  CACHE_VERSION = 1      # bump when parsing changes, to re-read cached recordings

  # Column name (before ";", whitespace squeezed) → channel. First match wins,
  # so "RPM" (the displayed value) beats the per-magneto RPMLEFT/RPMRIGHT.
  CHANNELS = {
    "RPM" => [ :rpm, "RPM", "RPM" ], "RPMLEFT" => [ :rpm, "RPM", "RPM" ],
    "MAP" => [ :map, "Manifold pressure", "inHg" ],
    "FLOW" => [ :fuel_flow, "Fuel flow", "gph" ],
    "OIL P" => [ :oil_p, "Oil pressure", "psi" ],
    "OIL T" => [ :oil_t, "Oil temp", "°F" ],
    "FUEL P" => [ :fuel_p, "Fuel pressure", "psi" ],
    "VOLTS" => [ :volts, "Volts", "V" ],
    "AMPS" => [ :amps, "Amps", "A" ],
    "OAT" => [ :oat, "OAT", "°F" ],
    "CARB" => [ :carb, "Carb temp", "°F" ],
    "TIT" => [ :tit, "TIT", "°F" ],
    "FUEL L" => [ :fuel_l, "Fuel left", "gal" ],
    "FUEL R" => [ :fuel_r, "Fuel right", "gal" ],
    "FLT" => [ :flight_hours, "Flight hours", "hrs" ],
    "TACH" => [ :tach, "Tach", "hrs" ],
    "ENG" => [ :engine_hours, "Engine hours", "hrs" ]
  }.freeze
  CYLINDER = /\A(EGT|CHT)(\d{1,2})\z/

  Channel = Struct.new(:key, :label, :unit, :values, keyword_init: true)

  Recording = Struct.new(:format, :metadata, :times, :channels, keyword_init: true) do
    def [](key) = channels[key]&.values
    def samples = times.size
    def started_at = times.first
    def ended_at = times.last
    def duration = ended_at - started_at
    def egt_keys = channels.keys.grep(/\Aegt\d+\z/)
    def cht_keys = channels.keys.grep(/\Acht\d+\z/)
    def cylinders = [ egt_keys.size, cht_keys.size ].max
    def utc_offset = metadata[:utc_offset].to_i
    def local(time) = time && (time + utc_offset).utc # wall clock on the monitor

    # Indexes of samples with the engine running (all of them if there's no RPM).
    def running
      @running ||= (rpm = self[:rpm]) ? rpm.each_index.select { rpm[_1].to_f >= RUNNING_RPM } : times.each_index.to_a
    end

    def engine_start = running.any? ? times[running.first] : nil
    def engine_stop = running.any? ? times[running.last] : nil
    def run_time = running.any? ? engine_stop - engine_start : 0

    def first(key) = self[key]&.compact&.first
    def last(key) = self[key]&.compact&.last

    # [value, time] of the extreme while running.
    def max(key) = extreme(key, :max_by)
    def min(key) = extreme(key, :min_by)

    # Hottest cylinder: { value:, cylinder:, at: }.
    def hottest(kind)
      keys = kind == :egt ? egt_keys : cht_keys
      keys.filter_map { |k| (m = max(k)) && { value: m[0], at: m[1], cylinder: k.to_s[/\d+/].to_i } }.max_by { _1[:value] }
    end

    # Gallons burned, integrating fuel flow (gph) over time.
    def fuel_burned
      flow = self[:fuel_flow] or return nil
      total = 0.0
      times.each_cons(2).with_index do |(t0, t1), i|
        dt = t1 - t0
        next unless dt.positive? && dt <= MAX_GAP_SECONDS && flow[i] && flow[i + 1]
        total += (flow[i] + flow[i + 1]) / 2.0 * dt / 3600
      end
      total
    end

    # Chartkick series for the given channels, thinned to CHART_POINTS.
    def chart(*keys)
      step = [ (samples.to_f / CHART_POINTS).ceil, 1 ].max
      idx = (0...samples).step(step).to_a
      keys.filter_map do |key|
        ch = channels[key] or next
        { name: ch.label, data: idx.filter_map { |i| [ times[i], ch.values[i] ] unless ch.values[i].nil? } }
      end
    end

    # Higher-resolution data for the interactive viewer: times in ms after the
    # start, values rounded and with whole numbers as integers to keep it small.
    def detail(max_points: DETAIL_POINTS)
      step = [ (samples.to_f / max_points).ceil, 1 ].max
      idx = (0...samples).step(step).to_a
      start = times.first
      {
        started_at: (start.to_r * 1000).round,
        utc_offset: utc_offset,
        times: idx.map { ((times[_1] - start) * 1000).round },
        channels: channels.transform_values do |ch|
          { label: ch.label, unit: ch.unit, values: idx.map { |i| (v = ch.values[i]) && (v == v.round ? v.round : v.round(2)) } }
        end
      }
    end

    private

    def extreme(key, how)
      values = self[key] or return nil
      i = running.select { values[_1] }.public_send(how) { values[_1] } or return nil
      [ values[i], times[i] ]
    end
  end

  # Parsing an hour of data takes ~0.2s, so cache by blob (blobs are immutable).
  def self.parse_attachment(attachment)
    return nil unless attachment&.attached?
    Rails.cache.fetch([ "engine-data", CACHE_VERSION, attachment.blob.key ], expires_in: 30.days) do
      attachment.blob.open { |file| new(file.read, filename: attachment.filename.to_s).parse }
    end
  end

  def initialize(content, filename: nil)
    @content = content.to_s.dup.force_encoding("UTF-8").scrub.delete_prefix("﻿")
    @filename = filename.to_s
  end

  def parse
    lines = @content.lines.map(&:chomp)
    header_at = lines.index { _1.start_with?("TIME,") }
    unless header_at && @content[0, 500].match?(/CGR-30|Electronics International/i)
      raise Error, "Not a recognized engine monitor file (expected a CGR-30P/CGR-30C .csv recording)"
    end

    metadata = parse_metadata(lines[0...header_at])
    columns = map_columns(lines[header_at].split(","))
    width = lines[header_at].count(",") + 1
    local_date, utc_offset = clock(metadata)
    metadata[:utc_offset] = utc_offset

    times = []
    values = columns.to_h { |key, _| [ key, [] ] }
    previous = nil
    lines[(header_at + 1)..].each do |line|
      fields = line.split(",", -1)
      next unless fields.size == width && (hms = fields[0].strip).match?(/\A\d{1,2}:\d{2}:\d{2}\z/)

      local = Time.utc(local_date.year, local_date.month, local_date.day, *hms.split(":").map(&:to_i))
      local += 1.day while previous && local < previous - 12.hours # past midnight
      previous = local
      times << local - utc_offset
      columns.each { |key, i| values[key] << number(fields[i]) }
    end
    raise Error, "No data rows found" if times.size < 2

    channels = columns.keys.to_h do |key|
      label, unit = describe(key)
      [ key, Channel.new(key: key, label: label, unit: unit, values: values[key]) ]
    end
    channels.reject! { |_, ch| ch.values.all?(&:nil?) }
    Recording.new(format: "CGR-30", metadata: metadata, times: spread(times), channels: channels)
  end

  private

  # "Aircraft ID....: N12345" → { aircraft_id: "N12345" }
  def parse_metadata(lines)
    lines.each_with_object({}) do |line, meta|
      key, value = line.split(":", 2)
      next unless value
      name = key.delete(".").strip.downcase.gsub(/\W+/, "_")
      meta[name.to_sym] = value.strip.delete_suffix(",,").strip
    end
  end

  # Local date of the recording and its offset from UTC (Zulu - Local).
  def clock(meta)
    local = parse_time(meta[:local_time])
    zulu = parse_time(meta[:zulu_time])
    raise Error, "Recording has no start date (Local Time line missing)" unless local
    offset = zulu ? ((local - zulu) / 900).round * 900 : 0 # whole quarter hours
    [ local.to_date, offset ]
  end

  def parse_time(value)
    Time.strptime("#{value} UTC", "%Y/%m/%d %H:%M:%S %Z").utc if value.present?
  rescue ArgumentError
    nil
  end

  def map_columns(headers)
    headers.each_with_index.each_with_object({}) do |(header, i), cols|
      name = header.split(";").first.to_s.squeeze(" ").strip.upcase
      key = (m = CYLINDER.match(name)) ? :"#{m[1].downcase}#{m[2]}" : CHANNELS.dig(name, 0)
      cols[key] ||= i if key
    end
  end

  def describe(key)
    if (m = key.to_s.match(/\A(egt|cht)(\d+)\z/))
      [ "#{m[1].upcase} #{m[2]}", "°F" ]
    else
      CHANNELS.values.find { _1[0] == key }.drop(1)
    end
  end

  def number(value)
    Float(value.to_s.strip)
  rescue ArgumentError
    nil
  end

  # Rows are stamped to the second but logged several times a second; spread
  # each run of equal stamps evenly across its second so charts don't step.
  def spread(times)
    times.chunk_while { _1 == _2 }.flat_map do |run|
      run.each_with_index.map { |t, i| t + Rational(i, run.size) }
    end
  end
end

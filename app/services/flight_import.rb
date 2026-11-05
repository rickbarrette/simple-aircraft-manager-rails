require "roo"

# Imports historical flights from a spreadsheet (.xlsx or .csv) where each row
# holds the meter readings at the END of a flight:
#
#   Date | From | To | Tach Time | Hobbs Time | Oil Added | Fuel Added | Flight Time
#
# Flight duration is derived from the previous row's reading. Rows are processed
# in file order (not re-sorted), so a reading that goes backwards is reported as
# an error instead of silently reshuffled.
#
# Importing records history only: it does NOT add time to components (that
# would double-count). Optionally, the aircraft's meters are advanced to the
# last reading afterwards via a normal hours update.
class FlightImport
  class Error < StandardError; end

  EXTENSIONS = %w[xlsx csv].freeze
  BLANK_VALUES = [ "", "n", "no", "none", "-", "—", "0", "0.0" ].freeze
  LONG_FLIGHT_HOURS = 15
  DATE_FORMATS = [ "%m/%d/%y", "%m/%d/%Y", "%Y-%m-%d", "%m-%d-%y", "%m-%d-%Y", "%d-%b-%y", "%d-%b-%Y" ].freeze

  # Header aliases, matched after lowercasing and stripping non-letters.
  COLUMNS = {
    date: ->(h) { h == "date" || h.start_with?("date") },
    from: ->(h) { h.start_with?("from", "dep", "origin") },
    to: ->(h) { %w[to dest destination arr arrival arrive].include?(h) },
    tach: ->(h) { h.start_with?("tach") },
    hobbs: ->(h) { h.start_with?("hobbs", "hobs") },
    oil: ->(h) { h.start_with?("oil") },
    fuel: ->(h) { h.start_with?("fuel") },
    flight_time: ->(h) { h.include?("flighttime") || h.include?("duration") }
  }.freeze

  Row = Struct.new(:line, :date, :from, :to, :tach_out, :tach_in, :tach_time,
                   :hobbs_out, :hobbs_in, :hobbs_time, :oil, :fuel, :status, :messages, :baseline,
                   keyword_init: true) do
    def importable? = status.in?(%i[ok warning])
    def warn(msg) = (messages << msg; self.status = :warning if status == :ok)
    def error(msg) = (messages << msg; self.status = :error)
  end

  attr_reader :columns, :headers

  def initialize(aircraft, path:, filename:, starting_tach: nil, starting_hobbs: nil)
    @aircraft = aircraft
    @path = path.to_s
    @filename = filename.to_s
    @starting_tach = decimal(starting_tach, 1)
    @starting_hobbs = decimal(starting_hobbs, 1)
  end

  def rows
    @rows ||= build_rows
  end

  def importable = rows.select(&:importable?)
  def count(status) = rows.count { _1.status == status }
  def total_tach_hours = importable.sum(&:tach_time)
  def last_reading = importable.last
  def mapped?(column) = columns.key?(column)

  # Creates flight logs + oil/fuel records. Returns the number of flights imported.
  def import!(user:, update_aircraft_hours: false)
    flights = importable
    raise Error, "Nothing to import." if flights.empty?

    Aircraft.transaction do
      flights.each do |r|
        log = @aircraft.flight_logs.create!(
          user: user, date: r.date, departure_location: r.from, destination_location: r.to,
          tach_out: r.tach_out, tach_in: r.tach_in, tach_time: r.tach_time,
          hobbs_out: r.hobbs_out, hobbs_in: r.hobbs_in, hobbs_time: r.hobbs_time,
          oil_added: r.oil, fuel_added: r.fuel, notes: "Imported from #{@filename}"
        )
        { "oil" => r.oil, "fuel" => r.fuel }.each do |type, qty|
          next unless qty
          @aircraft.consumable_records.create!(record_type: type, flight_log: log, date: r.date,
                                               quantity_added: qty, flight_hours: r.tach_in,
                                               notes: "Imported from #{@filename}")
        end
      end
      @aircraft.log_event!("flight", "Imported #{flights.size} flights from spreadsheet", user: user,
                           notes: "#{@filename}: #{flights.first.date} – #{flights.last.date}, #{total_tach_hours} tach hrs")
    end

    advance_aircraft_hours!(user) if update_aircraft_hours
    flights.size
  end

  # Moves the aircraft's meters up to the last imported reading (never down).
  # Returns the delta applied, or nil if nothing changed.
  def advance_aircraft_hours!(user)
    last = last_reading
    return nil unless last && last.tach_in > @aircraft.tach_time
    hobbs = last.hobbs_in if last.hobbs_in && last.hobbs_in >= @aircraft.hobbs_time
    HoursService.new(@aircraft, user: user).update_hours!(tach_time: last.tach_in, hobbs_time: hobbs)
  end

  private

  def build_rows
    sheet, header_index = locate_header
    existing = @aircraft.flight_logs.where.not(tach_in: nil).pluck(:date, :tach_in).to_set { |d, t| [ d, t.to_d ] }
    prev_tach = @starting_tach
    prev_hobbs = @starting_hobbs
    result = []

    ((header_index + 1)..sheet.last_row).each do |i|
      raw = sheet.row(i)
      next if raw.compact.all? { _1.to_s.strip.empty? }

      row = Row.new(line: i, status: :ok, messages: [])
      row.date = parse_date(cell(raw, :date))
      row.from = code(cell(raw, :from))
      row.to = code(cell(raw, :to))
      row.tach_in = decimal(cell(raw, :tach), 1)
      row.hobbs_in = decimal(cell(raw, :hobbs), 1)
      row.oil = quantity(row, cell(raw, :oil), "Oil")
      row.fuel = quantity(row, cell(raw, :fuel), "Fuel")
      flight_time = decimal(cell(raw, :flight_time), 1)

      row.error("Date missing or not recognized (#{cell(raw, :date).inspect})") unless row.date
      row.error("Tach reading missing") unless row.tach_in

      if row.tach_in
        if prev_tach.nil?
          if flight_time&.positive?
            row.tach_time = flight_time
            row.tach_out = row.tach_in - flight_time
            row.warn("First row: duration taken from Flight Time column (enter the starting tach to be exact)")
          else
            row.error("Starting reading only: no previous tach to measure from. Enter the tach before the first flight to import this row")
            row.baseline = true
          end
        elsif row.tach_in < prev_tach
          row.error("Tach went backwards (#{prev_tach} → #{row.tach_in}). Likely a typo")
        elsif row.tach_in == prev_tach
          row.tach_out = prev_tach
          row.tach_time = BigDecimal("0")
          row.warn("Tach didn't change (#{row.tach_in}). Imported as 0.0 hrs; check for a typo")
        else
          row.tach_out = prev_tach
          row.tach_time = row.tach_in - prev_tach
          row.warn("Long flight: #{row.tach_time} tach hrs. Missing rows?") if row.tach_time > LONG_FLIGHT_HOURS
        end
      end

      if row.hobbs_in && prev_hobbs && row.hobbs_in > prev_hobbs
        row.hobbs_out = prev_hobbs
        row.hobbs_time = row.hobbs_in - prev_hobbs
      elsif flight_time&.positive?
        row.hobbs_time = flight_time
      end
      if row.hobbs_in && prev_hobbs && row.hobbs_in < prev_hobbs
        row.warn("Hobbs went backwards (#{prev_hobbs} → #{row.hobbs_in}). Meter replaced?")
      end

      if row.status != :error && existing.include?([ row.date, row.tach_in ])
        row.status = :duplicate
        row.messages = [ "Already imported" ]
      end

      # Bad rows don't move the baseline, so the next good row absorbs the time.
      if row.status != :error || row.baseline
        prev_tach = row.tach_in
        prev_hobbs = row.hobbs_in if row.hobbs_in
      end
      result << row
    end
    result
  end

  def locate_header
    book = open_spreadsheet
    book.sheets.each do |name|
      sheet = book.sheet(name)
      next unless sheet.first_row
      (sheet.first_row..[ sheet.first_row + 20, sheet.last_row ].min).each do |i|
        cols = detect_columns(sheet.row(i))
        if cols.key?(:date) && cols.key?(:tach)
          @columns = cols
          @headers = sheet.row(i)
          return [ sheet, i ]
        end
      end
    end
    raise Error, "Couldn't find a header row with Date and Tach columns."
  end

  def open_spreadsheet
    ext = File.extname(@filename).delete(".").downcase
    raise Error, "Upload an .xlsx or .csv file." unless ext.in?(EXTENSIONS)
    Roo::Spreadsheet.open(@path, extension: ext.to_sym)
  rescue Zip::Error, ArgumentError, CSV::MalformedCSVError => e
    raise Error, "Couldn't read the file (#{e.message})."
  end

  def detect_columns(header_row)
    found = {}
    header_row.each_with_index do |h, idx|
      norm = h.to_s.downcase.gsub(/[^a-z]/, "")
      next if norm.empty?
      COLUMNS.each { |key, match| found[key] ||= idx if match.(norm) }
    end
    found
  end

  def cell(raw, key)
    idx = @columns[key]
    idx && raw[idx]
  end

  def parse_date(value)
    case value
    when Date, DateTime, Time then value.to_date
    when nil then nil
    else
      str = value.to_s.strip
      DATE_FORMATS.each do |fmt|
        date = Date.strptime(str, fmt) rescue next
        return date
      end
      nil
    end
  end

  def decimal(value, scale = 2)
    return nil if value.nil? || value.to_s.strip.empty?
    BigDecimal(value.to_s.strip.delete(",")).round(scale)
  rescue ArgumentError
    nil
  end

  def quantity(row, value, label)
    return nil if value.nil? || BLANK_VALUES.include?(value.to_s.strip.downcase)
    if value.to_s.strip.casecmp?("full")
      row.warn("#{label} “Full” has no quantity, so it isn't recorded")
      return nil
    end
    qty = decimal(value)
    if qty.nil? || qty.negative?
      row.warn("#{label} value #{value.inspect} ignored")
      return nil
    end
    qty
  end

  def code(value)
    value.to_s.strip.upcase.presence
  end
end

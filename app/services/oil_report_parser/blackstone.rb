class OilReportParser
  # Blackstone Laboratories report: one page with a header (lab number, unit ID,
  # oil type), the lab's comments, then a grid with one column per sample (newest
  # on the left, dated across the top) and one row per element / oil property.
  # Two extra columns hold averages: this unit's own (skipped) and the lab's
  # universal averages for the engine type (kept as the comparison average).
  #
  # Numbers are right-aligned under their sample dates, so values are matched to
  # a sample by their right edge.
  class Blackstone
    LAB = "Blackstone".freeze
    ELEMENTS = %w[aluminum chromium iron copper lead tin molybdenum nickel manganese silver titanium
                  potassium boron silicon sodium calcium magnesium phosphorus zinc barium].freeze
    PROPERTIES = {
      /\ASUS Viscosity/ => "viscosity_sus_210f", /\AcSt Viscosity/ => "viscosity_cst_100c",
      /\AFlashpoint/ => "flashpoint_f", /\AFuel %/ => "fuel_percent", /\AAntifreeze %/ => "antifreeze_percent",
      /\AWater %/ => "water_percent", /\AInsolubles %/ => "insolubles_percent",
      /\ATBN\z/ => "total_base_number", /\ATAN\z/ => "total_acid_number"
    }.freeze
    LABEL_MAX_X = 130   # row labels sit in the left margin
    ROW_SLOP = 3.5      # a row's values can sit a couple of points off its label's baseline
    COLUMN_SLOP = 8     # how far a value's right edge may be from its date's
    DATE = %r{\A\d{1,2}/\d{1,2}/\d{4}\z}
    # A US registration in the "unit ID" field; anything else (owners often put an
    # engine name there) isn't treated as a tail number.
    TAIL = /\AN[1-9][0-9A-Z]{0,4}\z/i

    Run = Struct.new(:text, :x, :endx, :y)

    def initialize(runs)
      # The vertical side captions ("UNIT INFORMATION"…) are single letters at x≈43.
      @runs = runs.filter_map { Run.new(_1.text.strip, _1.x, _1.endx, _1.y) if _1.x >= 48 && _1.text.strip.present? }
    end

    def parse
      date_label = label("Sample Date") or raise Error, I18n.t("services.oil_report.no_sample_dates_found_in")
      dates = row(date_label).select { DATE.match?(_1.text) }.sort_by(&:x)
      raise Error, I18n.t("services.oil_report.no_sample_dates_found_in") if dates.empty?
      @columns = dates.map(&:endx)
      @universal_x = (@runs.find { _1.text == "UNIVERSAL" }&.x || 530) - 10

      oil_hours, engine_hours, oil_added = [ "MI/HR on Oil", "MI/HR on Unit", "Make Up Oil Added" ].map { values(label(_1)) }
      elements, universal = ELEMENTS.each_with_object([ {}, {} ]) do |el, (by_el, avg)|
        by_el[el] = values(label(el.upcase))
        avg[el] = universal_value(label(el.upcase))
      end
      properties = PROPERTIES.to_h { |pattern, key| [ key, values(label(pattern)) ] }
      universal = universal.transform_values { OilReportParser.number(_1) }.compact
      lab_number = after("LAB NUMBER:")

      samples = dates.each_with_index.map do |date, i|
        {
          current: i.zero?,
          sample_date: OilReportParser.date(date.text),
          sample_number: (lab_number if i.zero?),
          oil_hours: OilReportParser.number(oil_hours[i]),
          engine_hours: OilReportParser.number(engine_hours[i]),
          oil_added: OilReportParser.number(oil_added[i]),
          status: nil, # Blackstone gives comments, not a rating
          lab_comments: (comments if i.zero?),
          elements: elements.transform_values { OilReportParser.number(_1[i]) }.compact,
          element_averages: universal,
          oil_properties: properties.transform_values { OilReportParser.number(_1[i]) }.compact
        }
      end.select { _1[:sample_date] }

      unit = after("UNIT ID:")
      Report.new(lab: LAB, tail_number: (unit if TAIL.match?(unit.to_s)), engine_serial: nil,
                 engine_model: after("MAKE/MODEL:"), oil_type: after("OIL TYPE & GRADE:"), samples: samples)
    end

    private

    # The left-margin run that labels a row.
    def label(match)
      @runs.find { _1.x < LABEL_MAX_X && (match.is_a?(Regexp) ? match.match?(_1.text) : _1.text == match) }
    end

    # Runs on the same row as a label, to its right.
    def row(label_run)
      return [] unless label_run
      @runs.select { (_1.y - label_run.y).abs <= ROW_SLOP && _1.x > label_run.endx }
    end

    # The row's value text for each sample column (nil where blank).
    def values(label_run)
      found = Array.new(@columns.size)
      row(label_run).each do |run|
        next if run.x >= @universal_x
        i = @columns.each_index.min_by { (@columns[_1] - run.endx).abs }
        found[i] ||= run.text if (@columns[i] - run.endx).abs <= COLUMN_SLOP
      end
      found
    end

    def universal_value(label_run) = row(label_run).find { _1.x >= @universal_x }&.text

    # The value printed after a header label, e.g. "UNIT ID:" → "N12345".
    def after(text)
      label_run = @runs.find { _1.text == text } or return nil
      @runs.select { (_1.y - label_run.y).abs <= 2 && _1.x > label_run.endx }.min_by(&:x)&.text
    end

    # The comment paragraph between the contact block and the results grid.
    # It starts with who it's addressed to ("OWNER:"), which is dropped.
    def comments
      contact = @runs.select { _1.text.match?(/\A(PHONE|FAX|ALT PHONE|EMAIL):/) }
      top = contact.map(&:y).min or return nil
      grid = label("MI/HR on Oil")&.y || 0
      lines = @runs.select { _1.y < top - 2 && _1.y > grid + 6 }.sort_by { [ -_1.y, _1.x ] }
      lines.map(&:text).join(" ").sub(/\A[A-Z]+:\s*/, "").squeeze(" ").presence
    end
  end
end

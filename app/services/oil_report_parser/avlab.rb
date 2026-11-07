class OilReportParser
  # Aviation Laboratories (AvLab) report. Each sample block has its dates,
  # hours, the lab's verdict, comments and a ppm table (value, lab average beneath).
  #
  # The PDF's text layer is messy: it hides the cell color codes ("#00CC00") as
  # larger text on top of the results. So this works from positioned characters,
  # drops the color-code layer by font size, rebuilds words and lines, and maps
  # each result to its element column by x position.
  class Avlab
    LAB = "AvLab".freeze
    COLOR_CODE_FONT_SIZE = 8.5 # the hidden color codes are 9pt; real text is 7–8pt
    WORD_GAP = 1.0             # glyphs closer than this are one word (spaces run 1.3pt+)
    COLUMNS = {
      "Iron" => "iron", "Copper" => "copper", "Nickel" => "nickel", "Chromium" => "chromium",
      "Silver" => "silver", "Magnesium" => "magnesium", "Aluminum" => "aluminum", "Lead" => "lead",
      "Silicon" => "silicon", "Titanium" => "titanium", "Tin" => "tin", "Moly." => "molybdenum"
    }.freeze
    LABELS = {
      "Sample Date:" => :sample_date, "Analysis Date:" => :analysis_date, "Sample Number:" => :sample_number,
      "TSN/TSO:" => :engine_hours, "Oil Hours:" => :oil_hours, "Filter Hours:" => :filter_hours,
      "Oil Added:" => :oil_added
    }.freeze
    LABEL_MAX_X = 108  # left-hand labels end before here…
    VALUE_X = 105..160 # …and their values sit in this column

    Char = Struct.new(:text, :x, :endx, :y, :page)
    Word = Struct.new(:text, :x, :endx, :y, :page) do
      def center = (x + endx) / 2.0
    end
    Line = Struct.new(:y, :page, :words) do
      def text = words.map(&:text).join(" ")
    end

    def self.from_receivers(receivers)
      chars = receivers.each_with_index.flat_map do |receiver, index|
        # Keep overlapping glyphs: a real "0" under a hidden one would otherwise be dropped.
        receiver.runs(merge: false, skip_overlapping: false).filter_map do |run|
          next if run.font_size >= COLOR_CODE_FONT_SIZE || run.text.strip.empty?
          Char.new(run.text, run.x, run.endx, run.y, index)
        end
      end
      new(chars).parse
    end

    def initialize(chars)
      @lines = build_lines(chars)
    end

    def parse
      unless @lines.any? { _1.text.include?("OIL ANALYSIS RESULTS IN PARTS PER MILLION") }
        raise Error, "Not an AvLab oil analysis report"
      end
      samples = sample_blocks.map { parse_sample(_1) }.select { _1[:sample_date] }
      raise Error, "No samples found in the report" if samples.empty?

      Report.new(lab: LAB, tail_number: after("Tail No.:"), engine_serial: after("Engine S/N:"),
                 engine_model: after("Engine Model:", words: 3), samples: samples)
    end

    private

    # Characters → lines (same baseline ±1pt) → words (glyphs closer than a space).
    def build_lines(chars)
      lines = []
      chars.sort_by { [ _1.page, -_1.y ] }.each do |c|
        line = lines.reverse_each.find { _1.page == c.page && (_1.y - c.y).abs <= 1.0 }
        line ? line.words << c : lines << Line.new(c.y, c.page, [ c ])
      end
      lines.each do |line|
        line.words = line.words.sort_by(&:x).each_with_object([]) do |c, words|
          last = words.last
          if last && c.x - last.endx <= WORD_GAP
            last.text += c.text
            last.endx = c.endx
          else
            words << Word.new(c.text.dup, c.x, c.endx, c.y, c.page)
          end
        end
      end
    end

    def header_lines
      first = @lines.find { _1.words.first&.text.in?(%w[CURRENT PREVIOUS]) }
      first ? @lines.take_while { _1 != first } : @lines
    end

    # The word(s) following a label on the same line, e.g. "Tail No.:" → "N12345".
    def after(label, words: 1)
      parts = label.split
      header_lines.each do |line|
        texts = line.words.map(&:text)
        texts.each_cons(parts.size).with_index do |window, i|
          next unless window == parts
          found = texts[i + parts.size, words]&.take_while { !_1.end_with?(":") }
          return found.join(" ").presence if found&.any?
        end
      end
      nil
    end

    # Lines from each "CURRENT SAMPLE" / "PREVIOUS SAMPLE n" heading to the next.
    def sample_blocks
      starts = @lines.each_index.select { |i| @lines[i].words.first&.text.in?(%w[CURRENT PREVIOUS]) && @lines[i].words[1]&.text == "SAMPLE" }
      starts.each_with_index.map { |s, n| @lines[s...(starts[n + 1] || @lines.size)] }
    end

    def parse_sample(block)
      heading = block.first
      verdict = heading.words.select { _1.x > 140 && _1.x < 470 }.map(&:text).join(" ")
      fields = labeled_values(block)
      comments = comments(block)
      elements, averages = results(block)

      {
        current: heading.words.first.text == "CURRENT",
        sample_date: OilReportParser.date(fields[:sample_date]),
        analysis_date: OilReportParser.date(fields[:analysis_date]),
        sample_number: fields[:sample_number],
        engine_hours: OilReportParser.number(fields[:engine_hours]),
        oil_hours: OilReportParser.number(fields[:oil_hours]),
        filter_hours: OilReportParser.number(fields[:filter_hours]),
        oil_added: OilReportParser.number(fields[:oil_added]),
        status: status(verdict),
        lab_comments: [ (verdict unless status(verdict) == "normal"), comments ].compact_blank.join("\n").presence,
        elements: elements,
        element_averages: averages
      }
    end

    # Left-hand "Label:" lines and the values beside them. A value isn't always on
    # the label's baseline, so each value goes to the nearest label above or below.
    # Every label counts, including ones we don't keep (e.g. "Filter Wt. (mgs):"),
    # so their values don't drift onto a neighbouring label.
    def labeled_values(block)
      labels = block.filter_map do |line|
        text = line.words.select { _1.x < LABEL_MAX_X - 20 || (_1.x < LABEL_MAX_X && _1.text.end_with?(":")) }.map(&:text).join(" ")
        [ LABELS[text], line.y ] if text.end_with?(":")
      end
      values = block.drop(1).flat_map { |line| line.words.select { VALUE_X.cover?(_1.x) } } # skip the heading
      values.each_with_object({}) do |word, found|
        key, = labels.min_by { (_2 - word.y).abs }
        found[key] ||= word.text if key
      end
    end

    # "Comments: …" and the lines that continue it at the same left margin.
    def comments(block)
      start = block.index { _1.words.first&.text == "Comments:" } or return nil
      first = block[start]
      margin = first.words.first.x
      lines = [ first.words.drop(1) ]
      block[(start + 1)..].each_with_index do |line, i|
        previous = block[start + i]
        break unless (line.words.first.x - margin).abs <= 3 && previous.y - line.y <= 14 && line.page == previous.page
        lines << line.words
      end
      lines.flatten.map(&:text).join(" ").presence
    end

    # The ppm row under the element headings, and the (average) row under that.
    def results(block)
      elements, averages = {}, {}
      header = block.find { |line| COLUMNS.keys.count { line.words.map(&:text).include?(_1) } >= 6 } or return [ elements, averages ]
      columns = header.words.filter_map { |w| [ COLUMNS[w.text], w.center ] if COLUMNS[w.text] }
      below = block.select { _1.y < header.y && _1.y > header.y - 25 }

      below.each do |line|
        # Results start right of the label column ("Cylinder Type: steel" shares these lines).
        merge_less_than(line.words.select { _1.x >= VALUE_X.end }).each do |word|
          element, = columns.min_by { (_2 - word.center).abs }
          if word.text.start_with?("(")
            averages[element] = ppm(word.text.delete("()"))
          else
            elements[element] = ppm(word.text)
          end
        end
      end
      [ elements.compact, averages.compact ]
    end

    # "<" and "0.1" are drawn as separate words.
    def merge_less_than(words)
      words.each_with_object([]) do |w, out|
        if out.last&.text == "<"
          out.last.text = "< #{w.text}"
          out.last.endx = w.endx
        else
          out << w.dup
        end
      end
    end

    # "N/A" → nil; "< 0.1" (below detection) → 0; ".3" → 0.3
    def ppm(text)
      return nil if text.blank? || text == "N/A"
      return 0 if text.start_with?("<")
      OilReportParser.number(text)
    end

    def status(verdict)
      case verdict.upcase
      when /ABNORMAL|HIGH|CRITICAL|SEVERE|PROBLEM/ then "action_required"
      when /APPEARS NORMAL/ then "normal"
      else "monitor"
      end
    end
  end
end

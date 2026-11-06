require "pdf-reader"

# Reads an AvLab (Aviation Laboratories) oil analysis report PDF. A report
# holds the current sample plus up to two previous ones, each with its dates,
# hours, lab verdict, comments and a ppm table (value, lab average beneath).
#
# The PDF's text layer is messy: it hides the cell color codes ("#00CC00") as
# larger text on top of the results. So this works from positioned characters,
# drops the color-code layer by font size, rebuilds words and lines, and maps
# each result to its element column by x position.
class OilReportParser
  class Error < StandardError; end

  LAB = "AvLab".freeze
  COLOR_CODE_FONT_SIZE = 8.5 # the hidden color codes are 9pt; real text is 7–8pt
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
  Report = Struct.new(:lab, :tail_number, :engine_serial, :engine_model, :samples, keyword_init: true)

  def self.from_pdf(io)
    reader = PDF::Reader.new(io)
    chars = reader.pages.each_with_index.flat_map do |page, index|
      receiver = PDF::Reader::PageTextReceiver.new
      page.walk(receiver)
      # Keep overlapping glyphs: a real "0" under a hidden one would otherwise be dropped.
      receiver.runs(merge: false, skip_overlapping: false).filter_map do |run|
        next if run.font_size >= COLOR_CODE_FONT_SIZE || run.text.strip.empty?
        Char.new(run.text, run.x, run.endx, run.y, index)
      end
    end
    new(chars).parse
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    raise Error, "Couldn't read the PDF (#{e.message})"
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
        if last && c.x - last.endx <= 1.6
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
    comments = block.find { _1.words.first&.text == "Comments:" }&.words&.drop(1)&.map(&:text)&.join(" ")

    {
      current: heading.words.first.text == "CURRENT",
      sample_date: date(fields[:sample_date]),
      analysis_date: date(fields[:analysis_date]),
      sample_number: fields[:sample_number],
      engine_hours: number(fields[:engine_hours]),
      oil_hours: number(fields[:oil_hours]),
      filter_hours: number(fields[:filter_hours]),
      oil_added: number(fields[:oil_added]),
      status: status(verdict),
      lab_comments: [ (verdict unless status(verdict) == "normal"), comments ].compact_blank.join("\n").presence
    }.merge(results(block))
  end

  # Left-hand "Label:" lines and the values beside them. A value isn't always on
  # the label's baseline, so each value goes to the nearest label above or below.
  def labeled_values(block)
    labels = block.filter_map do |line|
      text = line.words.select { _1.x < LABEL_MAX_X - 20 || (_1.x < LABEL_MAX_X && _1.text.end_with?(":")) }.map(&:text).join(" ")
      [ LABELS[text], line.y ] if LABELS[text]
    end
    values = block.drop(1).flat_map { |line| line.words.select { VALUE_X.cover?(_1.x) } } # skip the heading
    values.each_with_object({}) do |word, found|
      key, = labels.min_by { (_2 - word.y).abs }
      found[key] ||= word.text if key
    end
  end

  # The ppm row under the element headings, and the (average) row under that.
  def results(block)
    header = block.find { |line| COLUMNS.keys.count { line.words.map(&:text).include?(_1) } >= 6 } or return {}
    columns = header.words.filter_map { |w| [ COLUMNS[w.text], w.center ] if COLUMNS[w.text] }
    below = block.select { _1.y < header.y && _1.y > header.y - 25 }

    below.each_with_object({}) do |line, out|
      # Results start right of the label column ("Cylinder Type: steel" shares these lines).
      merge_less_than(line.words.select { _1.x >= VALUE_X.end }).each do |word|
        element, = columns.min_by { (_2 - word.center).abs }
        if word.text.start_with?("(")
          out[:"#{element}_avg"] = ppm(word.text.delete("()"))
        else
          out[element.to_sym] = ppm(word.text)
        end
      end
    end
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
    number(text)
  end

  def number(text)
    BigDecimal(text.to_s.strip.sub(/\A\./, "0."))
  rescue ArgumentError, TypeError
    nil
  end

  def date(text)
    Date.strptime(text, "%m/%d/%Y") if text
  rescue Date::Error
    nil
  end

  def status(verdict)
    case verdict.upcase
    when /ABNORMAL|HIGH|CRITICAL|SEVERE|PROBLEM/ then "high"
    when /APPEARS NORMAL/ then "normal"
    else "elevated"
    end
  end
end

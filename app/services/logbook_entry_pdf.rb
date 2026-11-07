require "prawn"
Prawn::Fonts::AFM.hide_m17n_warning = true # text is reduced to what the built-in fonts can show

# Logbook entries as a PDF to print and put in the paper logbook: on
# adhesive labels or on pages. Each entry carries what 14 CFR 43.9 / 43.11
# want (aircraft, date, time in service, the work, the signer's name and
# certificate) and a blank line for the signature, which must be signed by
# hand. On labels, long entries shrink to fit, then continue on the next
# label; on pages, entries follow one another, each with its signature line.
class LogbookEntryPdf
  IN = 72 # points per inch

  Layout = Data.define(:key, :label, :page, :cols, :rows, :width, :height, :left, :top, :col_gap, :row_gap, :padding) do
    def per_page = cols * rows
    def labels? = per_page > 1 || page != [ width, height ]
  end

  LAYOUTS = [
    Layout.new(key: "avery_5164", label: "Labels: Avery 5164 / 8164 (3⅓ × 4 in, 6 per sheet)", page: [ 8.5 * IN, 11 * IN ],
               cols: 2, rows: 3, width: 4 * IN, height: 3.333 * IN, left: 0.156 * IN, top: 0.5 * IN,
               col_gap: 0.188 * IN, row_gap: 0, padding: 0.15 * IN),
    Layout.new(key: "avery_5163", label: "Labels: Avery 5163 / 8163 (2 × 4 in, 10 per sheet)", page: [ 8.5 * IN, 11 * IN ],
               cols: 2, rows: 5, width: 4 * IN, height: 2 * IN, left: 0.156 * IN, top: 0.5 * IN,
               col_gap: 0.188 * IN, row_gap: 0, padding: 0.12 * IN),
    Layout.new(key: "half_letter", label: "Half-letter pages (5½ × 8½ in)", page: [ 5.5 * IN, 8.5 * IN ],
               cols: 1, rows: 1, width: 5.5 * IN, height: 8.5 * IN, left: 0, top: 0, col_gap: 0, row_gap: 0, padding: 0.5 * IN),
    Layout.new(key: "letter", label: "Letter pages (8½ × 11 in, also full-sheet labels)", page: [ 8.5 * IN, 11 * IN ],
               cols: 1, rows: 1, width: 8.5 * IN, height: 11 * IN, left: 0, top: 0, col_gap: 0, row_gap: 0, padding: 0.75 * IN)
  ].freeze

  def self.layout(key) = LAYOUTS.find { _1.key == key } || LAYOUTS.first

  def initialize(aircraft, entries, layout:, start_at: 1)
    @aircraft = aircraft
    @entries = entries
    @layout = self.class.layout(layout)
    @slot = (start_at.to_i - 1).clamp(0, @layout.per_page - 1) # skip used labels on the first sheet
  end

  def filename = "#{@aircraft.tail_number.downcase}-logbook-entries.pdf"

  def render
    info = { Title: "#{@aircraft.tail_number} logbook entries", Creator: "Simple Aircraft Manager" }
    if @layout.labels?
      @pdf = Prawn::Document.new(page_size: @layout.page, margin: 0, info: info)
      @entries.each { |entry| place(entry) }
    else
      @pdf = Prawn::Document.new(page_size: @layout.page, margin: @layout.padding, info: info)
      @entries.each_with_index { |entry, i| flow(entry, first: i.zero?) }
      @pdf.number_pages clean("#{@aircraft.tail_number}  ·  page <page> of <total>"), at: [ 0, -@layout.padding / 2 ], width: @pdf.bounds.width,
                                                                                  align: :right, size: 7, color: "777777"
    end
    @pdf.render
  end

  private

  # Pages: the entry's lines, then its signature block (kept together),
  # then a rule before the next one.
  def flow(entry, first:)
    small = 9
    w = @pdf.bounds.width
    unless first
      @pdf.move_down 10
      @pdf.stroke_color "BBBBBB"
      @pdf.stroke_horizontal_rule
      @pdf.move_down 12
    end
    @pdf.start_new_page if @pdf.cursor < 90 # don't strand a heading at the foot of a page
    @pdf.text clean(header_line), size: small, style: :bold
    @pdf.text clean("#{LogbookEntry::LOG_TYPES[entry.log_type]} log  ·  #{facts(entry).join('     ')}"), size: small
    @pdf.move_down 4
    @pdf.text clean(body_text(entry)), size: 11, leading: 1.5
    @pdf.move_down 10
    height = signature_block_height(small) + 14
    @pdf.start_new_page if @pdf.cursor < height
    @pdf.bounding_box([ 0, @pdf.cursor ], width: w, height: height) { signature_block(entry, w, height, small, more: false) }
  end

  def header_line
    [ @aircraft.tail_number, [ @aircraft.make, @aircraft.model ].compact_blank.join(" ").presence,
      (@aircraft.serial_number.present? ? "S/N #{@aircraft.serial_number}" : nil) ].compact.join("  ·  ")
  end

  def facts(entry)
    [ "Date: #{entry.date&.strftime('%b %-d, %Y')}",
      (entry.aircraft_hours_at_entry && "Total time: #{format('%.1f', entry.aircraft_hours_at_entry)} hrs (#{@aircraft.time_basis})") ].compact
  end

  def place(entry)
    remaining = body_text(entry)
    continued = false
    loop do
      box = next_box
      remaining = draw(entry, box, remaining, continued: continued)
      break if remaining.blank?
      continued = true
    end
  end

  # The next free label (or page): [x, y_top, width, height] inside the padding.
  def next_box
    if @slot >= @layout.per_page
      @pdf.start_new_page
      @slot = 0
    end
    col = @slot % @layout.cols
    row = @slot / @layout.cols
    @slot += 1
    x = @layout.left + col * (@layout.width + @layout.col_gap) + @layout.padding
    y = @layout.page[1] - @layout.top - row * (@layout.height + @layout.row_gap) - @layout.padding
    [ x, y, @layout.width - 2 * @layout.padding, @layout.height - 2 * @layout.padding ]
  end

  # Draws one label's worth; returns the body text that didn't fit.
  def draw(entry, (x, y, w, h), body, continued:)
    small = @layout.labels? ? 6.5 : 9
    base = @layout.labels? ? 8 : 11
    leftover = nil
    @pdf.bounding_box([ x, y ], width: w, height: h) do
      @pdf.text_box clean(header_line), at: [ 0, h ], width: w * 0.68, height: small + 2, size: small, style: :bold, overflow: :truncate
      @pdf.text_box clean("#{LogbookEntry::LOG_TYPES[entry.log_type]} log#{' (continued)' if continued}"),
                    at: [ w * 0.68, h ], width: w * 0.32, height: small + 2, size: small, align: :right, overflow: :truncate
      @pdf.text_box clean(facts(entry).join("     ")), at: [ 0, h - small - 3 ], width: w, height: small + 2, size: small, overflow: :truncate

      footer_h = signature_block_height(small)
      body_top = h - 2 * (small + 3) - 2
      body_h = body_top - footer_h - 4
      leftover = @pdf.text_box(clean(body), at: [ 0, body_top ], width: w, height: body_h, size: base, min_font_size: [ base - 2.5, 5.5 ].max,
                                            overflow: :shrink_to_fit, leading: 1)
      signature_block(entry, w, footer_h, small, more: leftover.present?)
    end
    leftover
  end

  def signature_block_height(small) = (small + 3) * 3 + 6

  def signature_block(entry, w, height, small, more:)
    @pdf.bounding_box([ 0, height ], width: w, height: height) do
      if more
        @pdf.text_box "Continued on the next label.", at: [ 0, height ], width: w, height: small + 2,
                                                                                         size: small, style: :italic, overflow: :truncate
      end
      line_y = height - (small + 3) * 1.6
      @pdf.stroke_color "555555"
      @pdf.stroke_horizontal_line 0, w * 0.62, at: line_y
      @pdf.text_box "Signature", at: [ 0, line_y - 1 ], width: w * 0.6, height: small, size: small - 1, overflow: :truncate
      @pdf.text_box clean(certificate(entry)), at: [ w * 0.64, line_y + small + 1 ], width: w * 0.36, height: small * 2 + 4,
                                                size: small, overflow: :shrink_to_fit, min_font_size: 5
      who = [ entry.signoff_person.presence || "Name: ____________________", entry.signoff_location.presence ].compact.join("  ·  ")
      @pdf.text_box clean(who), at: [ 0, line_y - small - 1 ], width: w, height: small + 2, size: small, overflow: :truncate
    end
  end

  def certificate(entry)
    kind = { "AP" => "A&P", "IA" => "A&P/IA", "A" => "A", "P" => "P", "REPAIR_STATION" => "Repair station", "REPAIRMAN" => "Repairman",
             "PILOT" => "Pilot", "OTHER" => "" }[entry.signoff_certificate_type].to_s
    number = entry.signoff_certificate_number.presence || "__________"
    "#{kind.presence || 'Cert.'} No. #{number}"
  end

  # The entry text, plus the 43.11(a)(5) statement for an inspection whose
  # result is recorded but whose text doesn't already certify it.
  def body_text(entry)
    text = entry.text.to_s.strip
    return text unless entry.entry_type == "INSPECTION" && entry.inspection_result.present? && !text.match?(/I certify/i)
    type = inspection_kind(entry, text)
    statement =
      if entry.inspection_result == "approved"
        "I certify that this aircraft has been inspected in accordance with #{type} inspection and was determined to be in airworthy condition."
      else
        "I certify that this aircraft has been inspected in accordance with #{type} inspection and a list of discrepancies and unairworthy items " \
          "dated #{entry.date&.strftime('%b %-d, %Y')} has been provided for the aircraft owner or operator."
      end
    "#{text}\n\n#{statement}"
  end

  # "an annual" / "a 100-hour": from a linked inspection record, else the text.
  def inspection_kind(entry, text)
    name = entry.inspection_records.first&.inspection_type&.name.to_s.sub(/\s*\(.*\)\z/, "").sub(/\s*inspection\z/i, "").strip.downcase
    name = "annual" if name.empty? && text.match?(/annual/i)
    name = "100-hour" if name.empty? && text.match?(/100[- ]?h(ou)?r/i)
    return "a ______________" if name.empty?
    "#{name.match?(/\A[aeiou]/) ? 'an' : 'a'} #{name}"
  end

  # The built-in PDF fonts cover Windows-1252; anything else becomes "?".
  def clean(text)
    text.to_s.unicode_normalize(:nfc).encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  end
end

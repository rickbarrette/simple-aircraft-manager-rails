require "prawn"
Prawn::Fonts::AFM.hide_m17n_warning = true # text is reduced to what the built-in fonts can show

# Logbook entries as a PDF to print and put in the paper logbook: on
# adhesive labels or on pages. Each entry carries what 14 CFR 43.9 / 43.11
# want (aircraft, date, airframe total time, the work, the signer's name and
# certificate) and a blank line for the signature, which must be signed by
# hand. Engine and propeller entries add the component's serial number, total
# time and time since overhaul (blanks to fill in when no component is linked),
# and a line for each sub-component the entry covers (an oil filter…).
#
# Labels: one entry per label; long entries shrink to fit, then continue on
# the next label. Pages: entries follow one another, each in a box with its
# signature line; one too long for a page continues in a box on the next.
class LogbookEntryPdf
  IN = 72 # points per inch

  Layout = Data.define(:key, :page, :cols, :rows, :width, :height, :left, :top, :col_gap, :row_gap, :padding) do
    def label = I18n.t(key, scope: "services.logbook_entry_pdf.layouts")
    def per_page = cols * rows
    def labels? = per_page > 1 || page != [ width, height ]
  end

  LAYOUTS = [
    Layout.new(key: "avery_5164", page: [ 8.5 * IN, 11 * IN ],
               cols: 2, rows: 3, width: 4 * IN, height: 3.333 * IN, left: 0.156 * IN, top: 0.5 * IN,
               col_gap: 0.188 * IN, row_gap: 0, padding: 0.15 * IN),
    Layout.new(key: "avery_5163", page: [ 8.5 * IN, 11 * IN ],
               cols: 2, rows: 5, width: 4 * IN, height: 2 * IN, left: 0.156 * IN, top: 0.5 * IN,
               col_gap: 0.188 * IN, row_gap: 0, padding: 0.12 * IN),
    Layout.new(key: "half_letter", page: [ 5.5 * IN, 8.5 * IN ],
               cols: 1, rows: 1, width: 5.5 * IN, height: 8.5 * IN, left: 0, top: 0, col_gap: 0, row_gap: 0, padding: 0.4 * IN),
    Layout.new(key: "letter", page: [ 8.5 * IN, 11 * IN ],
               cols: 1, rows: 1, width: 8.5 * IN, height: 11 * IN, left: 0, top: 0, col_gap: 0, row_gap: 0, padding: 0.6 * IN)
  ].freeze

  # Type sizes: [small (details), body, smallest body when shrinking].
  LABEL_SIZES = [ 6.5, 8, 5.5 ].freeze
  PAGE_SIZES = [ 9, 11, 11 ].freeze
  BOX_PADDING = 8 # inside a page entry's box
  BOX_GAP = 12    # between boxes

  def self.layout(key) = LAYOUTS.find { _1.key == key } || LAYOUTS.first

  def initialize(aircraft, entries, layout:, start_at: 1)
    @aircraft = aircraft
    @entries = entries
    @layout = self.class.layout(layout)
    @slot = (start_at.to_i - 1).clamp(0, @layout.per_page - 1) # skip used labels on the first sheet
  end

  def filename = "#{@aircraft.tail_number.downcase}-logbook-entries.pdf"

  def t(key, **opts) = I18n.t(key, scope: "services.logbook_entry_pdf", **opts)

  def render
    info = { Title: t(:title, tail_number: @aircraft.tail_number), Creator: "Simple Aircraft Manager" }
    if @layout.labels?
      @pdf = Prawn::Document.new(page_size: @layout.page, margin: 0, info: info)
      @entries.each { place_on_labels(_1) }
    else
      @pdf = Prawn::Document.new(page_size: @layout.page, margin: @layout.padding, info: info)
      @entries.each { place_on_pages(_1) }
      @pdf.number_pages clean(t(:page_number, tail_number: @aircraft.tail_number)), at: [ 0, -@layout.padding / 2 ],
                                                                                  width: @pdf.bounds.width, align: :right, size: 7, color: "777777"
    end
    @pdf.render
  end

  private

  # ---- Labels ----

  def place_on_labels(entry)
    remaining = body_text(entry)
    continued = false
    loop do
      remaining = draw(entry, next_label, remaining, continued: continued, sizes: LABEL_SIZES, shrink: true, continue_note: "label")
      break if remaining.blank?
      continued = true
    end
  end

  # The next free label: [x, y_top, width, height] inside its padding.
  def next_label
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

  # ---- Pages ----

  def place_on_pages(entry)
    remaining = body_text(entry)
    continued = false
    w = @pdf.bounds.width
    loop do
      needed = box_height(entry, remaining, w)
      # A new page if the box doesn't fit here but would on a fresh page, or
      # too little of this page is left to be worth starting it.
      @pdf.start_new_page if needed > @pdf.cursor && (needed <= @pdf.bounds.height || @pdf.cursor < 160)
      h = [ needed, @pdf.cursor ].min
      top = @pdf.cursor
      @pdf.stroke_color "444444"
      @pdf.line_width 0.75
      @pdf.stroke_rectangle [ 0, top ], w, h
      inner = [ BOX_PADDING, top - BOX_PADDING, w - 2 * BOX_PADDING, h - 2 * BOX_PADDING ]
      remaining = draw(entry, inner, remaining, continued: continued, sizes: PAGE_SIZES, shrink: false, continue_note: "page")
      @pdf.move_cursor_to([ top - h - BOX_GAP, 0 ].max)
      break if remaining.blank?
      @pdf.start_new_page
      continued = true
    end
  end

  def box_height(entry, body, width)
    small, base, = PAGE_SIZES
    body_h = @pdf.height_of(clean(body), width: width - 2 * BOX_PADDING, size: base, leading: 1.5)
    head_h = (detail_lines(entry).size + 1) * (small + 3) + 2
    head_h + body_h + 8 + signature_block_height(small) + 2 * BOX_PADDING
  end

  # ---- One entry in an area (a label, or the inside of a page box) ----

  # Draws the entry into [x, y_top, w, h]; returns the body text that didn't fit.
  def draw(entry, (x, y, w, h), body, continued:, sizes:, shrink:, continue_note:)
    small, base, min = sizes
    leftover = nil
    @pdf.bounding_box([ x, y ], width: w, height: h) do
      @pdf.text_box clean(header_line), at: [ 0, h ], width: w * 0.68, height: small + 2, size: small, style: :bold, overflow: :truncate
      @pdf.text_box clean(t(continued ? :log_continued : :log, log: LogbookEntry::LOG_TYPES[entry.log_type])),
                    at: [ w * 0.68, h ], width: w * 0.32, height: small + 2, size: small, align: :right, overflow: :truncate
      line_y = h - small - 3
      detail_lines(entry).each do |line|
        @pdf.text_box clean(line), at: [ 0, line_y ], width: w, height: small + 2, size: small,
                                   overflow: :shrink_to_fit, min_font_size: small - 1.5
        line_y -= small + 3
      end

      footer_h = signature_block_height(small)
      body_top = line_y - 2
      fitting = { at: [ 0, body_top ], width: w, height: body_top - footer_h - 4, size: base }
      fitting = shrink ? fitting.merge(leading: 1, overflow: :shrink_to_fit, min_font_size: min) : fitting.merge(leading: 1.5, overflow: :truncate)
      leftover = @pdf.text_box(clean(body), **fitting)
      signature_block(entry, w, footer_h, small, more: leftover.present? ? continue_note : nil)
    end
    leftover
  end

  def header_line
    [ @aircraft.tail_number, [ @aircraft.make, @aircraft.model ].compact_blank.join(" ").presence,
      (@aircraft.serial_number.present? ? t(:serial, serial: @aircraft.serial_number) : nil) ].compact.join("  ·  ")
  end

  # Date and airframe total time; for engine / propeller entries (or any with
  # a component) the component's serial number, total time and since overhaul.
  def detail_lines(entry)
    airframe = entry.aircraft_hours_at_entry ? "#{hrs(entry.aircraft_hours_at_entry)} (#{@aircraft.time_basis})" : "________"
    lines = [ t(:date_line, date: entry.date && I18n.l(entry.date, format: :app), airframe: airframe) ]
    component = entry.component
    noun = component_noun(entry, component)
    if component
      model = [ component.manufacturer, component.model ].compact_blank.join(" ")
      serial = "  #{t(:serial, serial: component.serial_number.presence || '__________')}"
      lines << [ "#{noun}: #{model}#{serial}",
                 t(:component_total_time, noun: noun, hours: blank_or_hours(entry.component_hours_at_entry)),
                 "#{component.since_overhaul_abbreviation}: #{blank_or_hours(entry.component_since_overhaul_at_entry)}" ].join("     ")
    elsif noun
      lines << t(:component_blank, noun: noun)
    end
    entry.parts.each do |part|
      c = part.component
      name = c.component_type&.name || t(:part)
      model = [ c.manufacturer, c.model ].compact_blank.join(" ")
      lines << [ "#{name}: #{model}#{"  #{t(:serial, serial: c.serial_number)}" if c.serial_number.present?}",
                 t(:total_time, hours: blank_or_hours(part.hours_at_entry)),
                 "#{c.since_overhaul_abbreviation}: #{blank_or_hours(part.since_overhaul_at_entry)}" ].join("     ")
    end
    lines
  end

  def component_noun(entry, component)
    return t(:engine) if component&.engine? || (component.nil? && entry.log_type == "ENG")
    return t(:propeller) if component&.propeller? || (component.nil? && entry.log_type == "PROP")
    component&.component_type&.name
  end

  def blank_or_hours(value) = value ? hrs(value) : "________"
  def hrs(value) = ActiveSupport::NumberHelper.number_to_delimited(format("%.1f", value))

  def signature_block_height(small) = (small + 3) * 3 + 6

  def signature_block(entry, w, height, small, more:)
    return electronic_signature_block(entry, w, height, small, more: more) if entry.signature
    @pdf.bounding_box([ 0, height ], width: w, height: height) do
      if more
        @pdf.text_box clean(t(:"continued_#{more}")), at: [ 0, height ], width: w, height: small + 2, size: small,
                                                        style: :italic, overflow: :truncate
      end
      line_y = height - (small + 3) * 1.6
      @pdf.stroke_color "555555"
      @pdf.line_width 0.5
      @pdf.stroke_horizontal_line 0, w * 0.62, at: line_y
      @pdf.text_box clean(t(:signature)), at: [ 0, line_y - 1 ], width: w * 0.6, height: small, size: small - 1, overflow: :truncate
      @pdf.text_box clean(certificate(entry)), at: [ w * 0.64, line_y + small + 1 ], width: w * 0.36, height: small * 2 + 4,
                                                size: small, overflow: :shrink_to_fit, min_font_size: 5
      who = [ entry.signoff_person.presence || t(:name_blank), entry.signoff_location.presence ].compact.join("  ·  ")
      @pdf.text_box clean(who), at: [ 0, line_y - small - 1 ], width: w, height: small + 2, size: small, overflow: :truncate
    end
  end

  # Signed entries: who certified it, when, and the fingerprint to check it by.
  def electronic_signature_block(entry, w, height, small, more:)
    sig = entry.signature
    @pdf.bounding_box([ 0, height ], width: w, height: height) do
      top = height
      if more
        @pdf.text_box clean(t(:"continued_#{more}")), at: [ 0, top ], width: w, height: small + 2, size: small, style: :italic, overflow: :truncate
      end
      top -= small + 3
      @pdf.text_box clean("#{EntrySignature.label} #{sig.signer_name}, #{sig.certificate_label} #{sig.certificate_number}" \
                          "#{"  #{t(:superseded)}" if entry.superseded?}"),
                    at: [ 0, top ], width: w, height: small + 2, size: small, style: :bold, overflow: :shrink_to_fit, min_font_size: 5
      top -= small + 3
      @pdf.text_box clean(t(:signed_electronically, time: sig.signed_at.utc.strftime("%Y-%m-%d %H:%M UTC"), fingerprint: sig.content_digest.first(16))),
                    at: [ 0, top ], width: w, height: small + 2, size: small - 1, overflow: :shrink_to_fit, min_font_size: 5
    end
  end

  def certificate(entry)
    kind = (t(entry.signoff_certificate_type, scope: "services.logbook_entry_pdf.certificate_kinds", default: "") if entry.signoff_certificate_type.present?)
    t(:certificate_number, kind: kind.presence || t(:certificate), number: entry.signoff_certificate_number.presence || "__________")
  end

  # The entry text, plus the 43.11(a)(5) statement for an inspection whose
  # result is recorded but whose text doesn't already certify it.
  def body_text(entry)
    text = entry.text.to_s.strip
    return "#{text}\n\n#{entry.signature.statement}" if entry.signature
    return text unless entry.entry_type == "INSPECTION" && entry.inspection_result.present? && !text.match?(/I certify/i)
    "#{text}\n\n#{entry.certification_statement(entry.signoff_certificate_type)}"
  end

  # The built-in PDF fonts cover Windows-1252; anything else becomes "?".
  def clean(text)
    text.to_s.unicode_normalize(:nfc).encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")
  end
end

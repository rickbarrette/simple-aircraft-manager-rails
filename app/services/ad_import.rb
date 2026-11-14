require "roo"

# Imports Airworthiness Directives from an FAA DRS (drs.faa.gov) export
# (.csv or .xlsx) for one aircraft. Each row becomes a shared
# AirworthinessDirective linked to the aircraft (matched by AD number, so
# re-imports and ADs entered by hand aren't duplicated).
#
# Per AD the owner chooses: track (needs a compliance record), not applicable
# (records an N/A determination), or skip. The preview suggests a choice and
# flags things worth checking: non-current/superseded ADs, a model that isn't
# listed, appliance or STC-only ADs, repetitive actions, and older ADs this
# one supersedes that the aircraft still tracks.
class AdImport
  class Error < StandardError; end

  ACTIONS = LabelSet.new("ad_import.actions", %w[track na skip])
  def self.na_note = I18n.t("services.ad_import.na_note")

  # DRS export headers, normalized (lowercase letters only).
  HEADERS = {
    number: "adnumber", heading: "subjectheading", subject: "subject", status: "status",
    effective_date: "effectivedate", docket: "docketnumber", models: "model",
    product_type: "producttype", supersedes: "supersededad", superseded_by: "supersededby",
    summary: "summary"
  }.freeze

  # AD attributes that come from the FAA and are refreshed on every import:
  # attribute => [label shown in the preview, value from the row].
  FAA_FIELDS = {
    short_description: [ :short_description, ->(r) { r.subject.to_s.truncate(254).presence } ],
    required_action: [ :required_action, ->(r) { r.summary } ],
    effective_date: [ :effective_date, ->(r) { r.effective_date } ],
    docket_number: [ :docket_number, ->(r) { r.docket } ],
    supersedes: [ :supersedes, ->(r) { r.supersedes.join(", ").presence } ],
    superseded_by: [ :superseded_by, ->(r) { r.superseded_by.join(", ").presence } ],
    applicable_models: [ :applicable_models, ->(r) { r.models.join(", ").presence } ],
    product_type: [ :product_type, ->(r) { r.product_type } ],
    document_url: [ :document_url, ->(r) { r.url } ]
  }.freeze

  Row = Struct.new(:line, :number, :subject, :status, :effective_date, :docket, :models, :product_type,
                   :supersedes, :superseded_by, :summary, :url, :existing, :tracked, :suggested, :notes, :changes,
                   keyword_init: true) do
    def note(msg) = notes << msg
  end

  def initialize(aircraft, path:, filename:)
    @aircraft = aircraft
    @path = path.to_s
    @filename = filename.to_s
  end

  def rows
    @rows ||= build_rows
  end

  def count(action) = rows.count { _1.suggested == action }

  # decisions: { "AD number" => "track" | "na" | "skip" }; missing → suggested.
  # "track" on an AD that's already tracked means "update it from the file".
  # Returns { tracked:, not_applicable:, skipped:, updated: }.
  def import!(decisions:, user:)
    result = { tracked: 0, not_applicable: 0, skipped: 0, updated: 0 }
    AirworthinessDirective.transaction do
      rows.each do |row|
        action = decisions.fetch(row.number, row.suggested).to_s
        action = "skip" unless ACTIONS.key?(action)
        if action == "skip"
          result[:skipped] += 1
          next
        end

        ad = upsert_ad(row)
        result[:updated] += 1 if row.existing && row.changes.any?
        ad.aircraft << @aircraft unless ad.aircraft.include?(@aircraft)
        if action == "na"
          unless ad.latest_compliance_for(@aircraft)&.not_applicable?
            ad.ad_compliances.create!(aircraft: @aircraft, date_complied: Date.current,
                                      not_applicable: true, compliance_notes: AdImport.na_note)
          end
          result[:not_applicable] += 1
        else
          result[:tracked] += 1
        end
      end
      imported = result[:tracked] + result[:not_applicable]
      raise Error, I18n.t("services.ad_import.nothing_selected") if imported.zero?
      @aircraft.log_event!("ad", "Imported #{imported} ADs from FAA DRS", user: user,
                           notes: I18n.t("services.ad_import.event_notes", file: @filename, tracked: result[:tracked], not_applicable: result[:not_applicable], skipped: result[:skipped]))
    end
    result
  end

  private

  def build_rows
    sheet, header_index, cols = locate_header
    tracked_numbers = @aircraft.applicable_ads.pluck(:name).map { AirworthinessDirective.normalize_number(_1) }.to_set
    # Accept "150L" or "Cessna 150L" as the aircraft's model.
    model = AirworthinessDirective.normalize_number(@aircraft.model)
    model_names = [ model, model.split.last ].compact_blank.uniq

    ((header_index + 1)..sheet.last_row).filter_map do |i|
      raw = sheet.row(i)
      number = AirworthinessDirective.normalize_number(raw[cols[:number]])
      next if number.empty?

      cell = ->(key) { (idx = cols[key]) ? raw[idx] : nil }
      row = Row.new(
        line: i, number: number,
        subject: text(cell.(:subject)).presence || text(cell.(:heading)),
        status: text(cell.(:status)),
        effective_date: parse_date(cell.(:effective_date)),
        docket: text(cell.(:docket)).then { _1 == "Unknown" ? nil : _1.presence },
        models: list(cell.(:models)),
        product_type: text(cell.(:product_type)).presence,
        supersedes: list(cell.(:supersedes)),
        superseded_by: list(cell.(:superseded_by)),
        summary: clean_summary(cell.(:summary)),
        url: row_link(sheet, i, raw, cols),
        notes: []
      )
      row.existing = AirworthinessDirective.find_by_number(number)
      row.tracked = tracked_numbers.include?(number)
      row.changes = row.existing ? changed_fields(row.existing, row) : []
      row.suggested = "track"

      if row.existing
        prefix = I18n.t(row.tracked ? "services.ad_import.already_tracked" : "services.ad_import.will_link")
        row.note(row.changes.any? ? I18n.t("services.ad_import.will_update", prefix: prefix, fields: row.changes.join(", ")) : I18n.t("services.ad_import.up_to_date", prefix: prefix))
      end

      # Reasons not to add a NEW AD. An AD that's already tracked is still
      # updated (so supersession and links reach it), just flagged for review.
      skip_reasons = []
      skip_reasons << I18n.t("services.ad_import.faa_status", status: row.status) if row.status.present? && !row.status.casecmp?("current")
      skip_reasons << I18n.t("services.ad_import.superseded_by", ads: row.superseded_by.join(", ")) if row.superseded_by.any?
      if model_names.any? && row.models.any? && (row.models.map { AirworthinessDirective.normalize_number(_1) } & model_names).empty?
        skip_reasons << I18n.t("services.ad_import.model_not_listed", model: @aircraft.model)
      end
      skip_reasons.each { row.note(row.tracked ? I18n.t("services.ad_import.review", reason: _1) : _1) }
      row.suggested = "skip" if skip_reasons.any? && !row.tracked
      if row.product_type&.casecmp?("appliance")
        row.note(I18n.t("services.ad_import.appliance"))
      end
      if row.summary =~ /Supplemental Type Certificate|\bSTC\b/i
        row.note(I18n.t("services.ad_import.stc"))
      end
      if row.summary =~ /repetitive|recurring|reinspect/i
        row.note(I18n.t("services.ad_import.repetitive"))
      end
      (row.supersedes & tracked_numbers.to_a).each do |old|
        row.note(I18n.t("services.ad_import.supersedes_tracked", ad: old))
      end
      row
    end
  end

  # FAA data is authoritative: every FAA field present in the file replaces
  # what's stored. Fields the file leaves blank are kept. Compliance records,
  # recurrence and applicability are never touched by an import.
  def upsert_ad(row)
    ad = row.existing || AirworthinessDirective.new(name: row.number, bulletin_type: "ad", mandatory: true)
    ad.assign_attributes(faa_attributes(row))
    ad.short_description = row.number if ad.short_description.blank?
    ad.save!
    ad
  end

  def faa_attributes(row)
    FAA_FIELDS.transform_values { |(_, value)| value.(row) }.compact
  end

  def changed_fields(ad, row)
    faa_attributes(row).filter_map { |attr, value| I18n.t(attr, scope: "services.ad_import.fields") if ad.public_send(attr) != value }
  end

  def locate_header
    book = open_spreadsheet
    book.sheets.each do |name|
      sheet = book.sheet(name)
      next unless sheet.first_row
      (sheet.first_row..[ sheet.first_row + 10, sheet.last_row ].min).each do |i|
        normalized = sheet.row(i).map { _1.to_s.downcase.gsub(/[^a-z]/, "") }
        next unless normalized.include?(HEADERS[:number])
        cols = HEADERS.transform_values { normalized.index(_1) }.compact
        link_col = normalized.index { _1.include?("link") || _1.include?("url") }
        cols[:url] = link_col if link_col
        return [ sheet, i, cols ]
      end
    end
    raise Error, I18n.t("services.ad_import.not_drs")
  end

  def open_spreadsheet
    ext = File.extname(@filename).delete(".").downcase
    raise Error, I18n.t("flash.uploads.spreadsheet_only") unless ext.in?(%w[xlsx csv])
    Roo::Spreadsheet.open(@path, extension: ext.to_sym)
  rescue Zip::Error, ArgumentError, CSV::MalformedCSVError => e
    raise Error, I18n.t("services.ad_import.unreadable", message: e.message)
  end

  # Link to the AD document: a hyperlink on any cell in the row (Excel exports),
  # a link/URL column, or a bare URL in any cell. Only http(s) links are kept.
  def row_link(sheet, line, raw, cols)
    candidates = []
    if sheet.respond_to?(:hyperlink)
      order = [ cols[:number], *raw.each_index.to_a ].compact.uniq
      candidates += order.map { |c| sheet.hyperlink(line, c + 1) rescue nil }
    end
    candidates << raw[cols[:url]] if cols[:url]
    candidates += raw.map(&:to_s)
    candidates.map { _1.to_s.strip }.find { _1.match?(%r{\Ahttps?://\S+\z}i) }
  end

  def text(value) = value.to_s.strip

  def list(value)
    text(value).split(/\s*[|;,]\s*/).map(&:strip).reject(&:empty?)
  end

  def parse_date(value)
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
    Date.strptime(value.to_s.strip, "%m/%d/%Y")
  rescue ArgumentError, TypeError
    nil
  end

  # Federal Register text arrives with literal "\n" sequences and page markers.
  def clean_summary(value)
    text(value).gsub(/\\n|\r?\n/, " ").gsub(/\(\(Page \d+\)\)/, " ").squeeze(" ").strip.presence
  end
end

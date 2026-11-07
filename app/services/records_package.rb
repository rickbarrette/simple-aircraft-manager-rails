require "csv"

# Everything about an aircraft's records in one ZIP, for the FAA or NTSB on
# request (91.417(c), AC 120-78B 3.2.8.6) or a buyer at sale (91.419,
# 3.2.8.12): the logbook entries as a PDF with their electronic signatures,
# a signature register, the full change history, the status report, and the
# data archive (.sam.zip) to load into another system.
class RecordsPackage
  def initialize(aircraft, source:)
    @aircraft = aircraft
    @source = source
    @generated_at = Time.current
  end

  def filename = "#{@aircraft.tail_number.downcase}-records-#{@generated_at.to_date.iso8601}.zip"

  def write_to(path)
    entries = @aircraft.logbook_entries.includes(:component, :parts, :signature, inspection_records: :inspection_type).order(:date, :id).to_a
    Zip::OutputStream.open(path) do |zip|
      add(zip, "README.txt", readme(entries))
      add(zip, "logbook-entries.pdf", LogbookEntryPdf.new(@aircraft, entries, layout: "letter").render) if entries.any?
      add(zip, "signatures.csv", signatures_csv(entries))
      add(zip, "record-history.csv", history_csv)
      add(zip, "status-report.html", status_report_html)
      if (revision = ProceduresRevision.current)
        add(zip, "recordkeeping-procedures.html", standalone_html(revision.content, "Recordkeeping procedures, revision #{revision.number}"))
      end
      archive = Tempfile.new([ "archive", ".sam.zip" ])
      AircraftArchive::Exporter.new(@aircraft, source: @source).write_to(archive.path)
      zip.put_next_entry("#{@aircraft.tail_number.downcase}.sam.zip")
      File.open(archive.path, "rb") { IO.copy_stream(_1, zip) }
    ensure
      archive&.close!
    end
    path
  end

  private

  def add(zip, name, content)
    zip.put_next_entry(name)
    zip.write(content)
  end

  def readme(entries)
    signed = entries.count(&:signed?)
    check = IntegrityCheck.latest
    <<~TXT
      Maintenance records for #{@aircraft.tail_number} (#{[ @aircraft.make, @aircraft.model ].compact_blank.join(' ')}, S/N #{@aircraft.serial_number.presence || 'not recorded'})
      Prepared #{@generated_at.utc.strftime('%Y-%m-%d %H:%M UTC')} by Simple Aircraft Manager (#{@source}), software version #{SystemInfo.new.revision}.

      Electronic records since: #{@aircraft.electronic_records_since&.iso8601 || 'not stated'}. Earlier records are the paper logbooks#{' (scans marked "legacy record" are in the archive)' if @aircraft.documents.where(legacy_record: true).exists?}.

      Contents
      - logbook-entries.pdf   All #{entries.size} logbook entries, oldest first. #{signed} are signed electronically: each shows
                              "Certified by" the signer and certificate, the time (UTC) and the first 16 characters of its fingerprint.
      - signatures.csv        Every electronic signature: signer, certificate, statement, time, status and full fingerprint.
      - record-history.csv    Every change to the maintenance records (created, changed, deleted), with who and when.
      - status-report.html    Maintenance status per 14 CFR 91.417(a)(2): times, life-limited parts, inspections, ADs, alterations.
      - #{@aircraft.tail_number.downcase}.sam.zip        All records and files as data, to load into another system.
      - recordkeeping-procedures.html  How these electronic records and signatures are kept (AC 120-78B), current adopted revision.

      Signatures
      Each electronic signature records who signed, with which certificate, what they certified, when, and a SHA-256
      fingerprint of the entry's content at signing. A signed entry can't be edited; corrections are new signed entries
      that supersede the original (both are included). Status "Valid" means the entry and signature are unchanged since
      signing; "Superseded" means a later signed correction replaces it.

      Last records integrity check: #{check ? "#{check.created_at.utc.strftime('%Y-%m-%d %H:%M UTC')}, #{check.ok ? 'no problems found' : "#{check.problems.size} problem(s) found"}" : 'not run yet'}.
    TXT
  end

  def signatures_csv(entries)
    CSV.generate do |csv|
      csv << %w[entry_date log entry_type signer certificate_kind certificate_number signed_at_utc status fingerprint statement corrects_entry_dated]
      entries.select(&:signed?).each do |e|
        s = e.signature
        csv << [ e.date, LogbookEntry::LOG_TYPES[e.log_type], LogbookEntry::ENTRY_TYPES[e.entry_type], s.signer_name, s.certificate_label,
                 s.certificate_number, s.signed_at.utc.iso8601, s.imported? ? "imported from #{s.origin}" : s.status_label,
                 s.content_digest, s.statement, e.supersedes&.date ]
      end
    end
  end

  def history_csv
    users = User.pluck(:id, :email_address).to_h
    CSV.generate do |csv|
      csv << %w[id at_utc record record_id event by changed_fields chain_hash]
      RecordVersion.where(aircraft_id: @aircraft.id).chronological.find_each do |v|
        csv << [ v.id, v.created_at.utc.iso8601, v.item_type.underscore.humanize, v.item_id, v.event, users[v.user_id] || "system",
                 v.event == "update" ? v.changed_fields.join(" ") : "", v.chain_hash ]
      end
    end
  end

  # The status report as one self-contained HTML file (styles inlined).
  def status_report_html
    inline_styles(ApplicationController.render("maintenance_reports/show", layout: "report", assigns: { report: MaintenanceReport.new(@aircraft), standalone: true }))
  end

  def standalone_html(body, title)
    inline_styles(ApplicationController.render(html: body.html_safe, layout: "report", assigns: { standalone: true }).sub(%r{<title>.*?</title>}m) { "<title>#{ERB::Util.h(title)}</title>" })
  end

  def inline_styles(html)
    css = %w[tailwind.css application.css].filter_map { Rails.application.assets.load_path.find(_1)&.content }.join("\n")
    # Block forms: a replacement string would treat "\\&" etc. in the CSS as back-references.
    html.gsub(%r{<link rel="stylesheet"[^>]*>\s*}) { "" }.sub("</head>") { "<style>#{css}</style></head>" }
        .gsub(%r{<script\b[^>]*>.*?</script>}m, "").gsub(%r{<link rel="modulepreload"[^>]*>\s*}, "")
  end
end

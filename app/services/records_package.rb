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
      add(zip, "viewer/docker-compose.yml", viewer_compose)
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

  # CSVs start with a UTF-8 byte order mark so Excel reads accents, dashes
  # and quotes correctly (without it, it guesses another encoding).
  def add(zip, name, content)
    content = "\uFEFF#{content}" if name.end_with?(".csv") && !content.start_with?("\uFEFF")
    zip.put_next_entry(name)
    zip.write(content)
  end

  def readme(entries)
    signed = entries.count(&:signed?)
    check = IntegrityCheck.latest
    t = ->(key, **opts) { I18n.t(key, scope: "services.records_package", **opts) }
    check_text =
      if check.nil? then t.(:check_none)
      else t.(check.ok ? :check_ok : :check_problems, time: check.created_at.utc.strftime("%Y-%m-%d %H:%M UTC"), count: check.problems.size)
      end
    t.(:readme, tail_number: @aircraft.tail_number, aircraft: [ @aircraft.make, @aircraft.model ].compact_blank.join(" "),
                serial: @aircraft.serial_number.presence || t.(:not_recorded), prepared: @generated_at.utc.strftime("%Y-%m-%d %H:%M UTC"),
                source: @source, version: SystemInfo.new.version_label, since: @aircraft.electronic_records_since&.iso8601 || t.(:not_stated),
                legacy: (@aircraft.documents.where(legacy_record: true).exists? ? t.(:legacy_note) : ""), count: entries.size, signed: signed,
                archive: "#{@aircraft.tail_number.downcase}.sam.zip", check: check_text,
                repository: (repository ? "\n#{t.(:repository, url: repository)}" : "")) + "\n"
  end

  def repository = SystemInfo.new.repository_url

  # The published image, as named in the project's docker-compose.image.yml
  # (APP_IMAGE overrides it, e.g. for a fork's own image).
  def viewer_image
    ENV["APP_IMAGE"].presence ||
      Rails.root.join("docker-compose.image.yml").then { _1.exist? ? _1.read[/^\s*image:\s*(\S+)/, 1] : nil }
  end

  # A ready-to-run local viewer, with its own throwaway secret key (never this
  # installation's), plain HTTP on localhost.
  def viewer_compose
    image = viewer_image
    <<~YAML
      # Simple Aircraft Manager on your own computer, to browse #{@aircraft.tail_number.downcase}.sam.zip.
      #   docker compose up -d   then open http://localhost:3000, create an account,
      #   and import #{@aircraft.tail_number.downcase}.sam.zip (Fleet -> Import). Stop: docker compose down
      # Prepared with software version #{SystemInfo.new.version_label}.#{" Source: #{repository}" if repository}
      services:
        web:
          #{image ? "image: #{image}" : "build: .   # no published image known: build from the source code"}
          restart: "no"
          ports:
            - "3000:80"
          environment:
            SECRET_KEY_BASE: #{SecureRandom.hex(64)}   # for this local copy only
            APP_HOST: localhost:3000
            FORCE_SSL: "false"
            SOLID_QUEUE_IN_PUMA: "true"
          volumes:
            - viewer_storage:/rails/storage
      volumes:
        viewer_storage:
    YAML
  end

  def signatures_csv(entries)
    CSV.generate do |csv|
      csv << %w[entry_date log entry_type signer certificate_kind certificate_number signed_at_utc status fingerprint statement corrects_entry_dated]
      entries.select(&:signed?).each do |e|
        s = e.signature
        csv << [ e.date, LogbookEntry::LOG_TYPES[e.log_type], LogbookEntry::ENTRY_TYPES[e.entry_type], s.signer_name, s.certificate_label,
                 s.certificate_number, s.signed_at.utc.iso8601, s.imported? ? I18n.t("services.records_package.imported_from", origin: s.origin) : s.status_label,
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

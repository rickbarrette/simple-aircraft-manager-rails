require "zip"

module AircraftArchive
  # Writes an aircraft and everything recorded for it to a .sam.zip.
  #
  #   AircraftArchive::Exporter.new(aircraft).write_to(path)
  class Exporter
    def initialize(aircraft, source: nil)
      @aircraft = aircraft
      @source = source
      @files = {} # archive path → attachment
      @missing = 0
    end

    attr_reader :missing # files that were attached but missing from storage

    def filename = "#{@aircraft.tail_number.to_s.downcase.gsub(/[^a-z0-9-]/, '')}-#{Date.current.iso8601}.sam.zip"

    def write_to(path)
      manifest = build_manifest
      Zip::OutputStream.open(path) do |zip|
        zip.put_next_entry("manifest.json")
        zip.write(JSON.pretty_generate(manifest))
        @files.each do |archive_path, attachment|
          zip.put_next_entry(archive_path)
          attachment.blob.download { zip.write(_1) }
        end
      end
      path
    end

    def build_manifest
      a = @aircraft
      components = a.components.includes(:component_type).to_a
      component_ids = components.map(&:id)
      inspection_types = (a.inspection_types.to_a + InspectionType.joins(:components).where(components: { id: component_ids }).to_a +
                          InspectionType.where(id: a.inspection_records.select(:inspection_type_id)).to_a).uniq
      ads = (a.airworthiness_directives.to_a + AirworthinessDirective.joins(:components).where(components: { id: component_ids }).to_a +
             AirworthinessDirective.where(id: a.ad_compliances.select(:airworthiness_directive_id)).to_a).uniq

      {
        schema_version: SCHEMA_VERSION,
        exported_at: Time.current.iso8601,
        source_instance: @source.to_s,
        aircraft: aircraft_hash(a),
        component_types: components.map(&:component_type).uniq.map { { id: id(_1), name: _1.name, consumable: _1.consumable } },
        components: components.map { component_hash(_1) },
        document_collections: a.document_collections.map do |c|
          { id: id(c), aircraft_id: id(a), name: c.name, description: c.description, visibility: c.visibility, starred: c.starred, components: [] }
        end,
        documents: a.documents.map do |d|
          { id: id(d), aircraft_id: id(a), collection_id: id(d.document_collection_id), doc_type: d.doc_type, name: d.name,
            description: d.description, visibility: d.visibility, components: [] }
        end,
        document_images: a.documents.includes(pages_attachments: :blob).flat_map do |d|
          d.pages.map { |page| { id: id(page), document_id: id(d), notes: "", image: file(page, "health/documents") } }
        end,
        logbook_entries: a.logbook_entries.map { logbook_hash(_1) },
        squawks: a.squawks.includes(:reported_by, attachments_attachments: :blob).map { squawk_hash(_1) },
        inspection_types: inspection_types.map { inspection_type_hash(_1, component_ids) },
        inspection_records: a.inspection_records.map do |r|
          { id: id(r), date: r.date&.iso8601, aircraft_hours: dec(r.aircraft_hours), inspection_type_id: id(r.inspection_type_id),
            logbook_entry_id: id(r.logbook_entry_id), aircraft_id: id(a), documents: [], component: [ id(r.component_id) ].compact,
            notes: r.notes }
        end,
        ads: ads.map { ad_hash(_1, component_ids) },
        ad_compliances: a.ad_compliances.map do |c|
          { id: id(c), ad_id: id(c.airworthiness_directive_id), date_complied: c.date_complied&.iso8601, compliance_notes: c.compliance_notes,
            permanent: c.permanent, next_due_at_time: dec(c.next_due_at_time), aircraft_hours_at_compliance: dec(c.aircraft_hours_at_compliance),
            logbook_entry_id: id(c.logbook_entry_id), inspection_record_id: id(c.inspection_record_id), aircraft_id: id(a),
            component_id: id(c.component_id), not_applicable: c.not_applicable }
        end,
        consumable_records: a.consumable_records.map do |r|
          { id: id(r), record_type: r.record_type, aircraft_id: id(a), date: r.date&.iso8601, quantity_added: dec(r.quantity_added),
            level_after: dec(r.level_after), consumable_type: r.consumable_type, flight_hours: dec(r.flight_hours), notes: r.notes,
            excluded_from_averages: r.excluded_from_averages, flight_log_id: id(r.flight_log_id) }
        end,
        major_records: a.major_records.map do |r|
          { id: id(r), aircraft_id: id(a), record_type: r.record_type, title: r.title, description: r.description,
            date_performed: r.date_performed&.iso8601, performed_by: r.performed_by, component_id: id(r.component_id),
            form_337_document_id: id(r.form_337_document_id), stc_number: r.stc_number, stc_holder: r.stc_holder,
            stc_document_id: id(r.stc_document_id), logbook_entry_id: id(r.logbook_entry_id), aircraft_hours: dec(r.aircraft_hours),
            notes: r.notes, has_ica: r.has_ica, ica_notes: r.ica_notes }
        end,
        notes: a.notes.includes(:user).map do |n|
          { id: id(n), aircraft_id: id(a), text: n.text, public: n.public, added_by_display: n.user&.display_name,
            added_timestamp: n.created_at&.iso8601, edited_at: n.edited_at&.iso8601 }
        end,
        oil_analysis_reports: a.oil_analyses.includes(report_attachment: :blob).map { oil_hash(_1) },
        flight_logs: a.flight_logs.includes(:user, track_log_attachment: :blob, engine_data_attachment: :blob).map { flight_hash(_1) },
        features: [ { feature: "airworthiness_enforcement", enabled: a.airworthiness_enforcement } ]
      }
    end

    private

    def id(record_or_id)
      value = record_or_id.respond_to?(:id) ? record_or_id.id : record_or_id
      value&.to_s
    end

    def dec(value) = value&.to_s

    # Queue an attachment for the archive and return its archive path. Each file
    # gets its own folder so original filenames survive. A file missing from
    # storage is left out (and counted) rather than failing the export.
    def file(attachable, folder)
      attachment = attachable.is_a?(ActiveStorage::Attachment) ? attachable : attachable&.attachment
      return nil unless attachment
      unless attachment.blob.service.exist?(attachment.blob.key)
        @missing += 1
        return nil
      end
      name = attachment.filename.sanitized.presence || "file"
      path = "attachments/#{folder}/#{attachment.blob.key}/#{name}"
      @files[path] = attachment
      path
    end

    def aircraft_hash(a)
      { id: id(a), tail_number: a.tail_number, make: a.make, model: a.model, serial_number: a.serial_number,
        description: a.description, purchased: a.purchased&.iso8601, status: a.status, tach_time: dec(a.tach_time),
        tach_time_offset: dec(a.tach_time_offset), hobbs_time: dec(a.hobbs_time), hobbs_time_offset: dec(a.hobbs_time_offset),
        picture: file(a.picture, "aircraft_pictures"), icao_type: a.icao_type }
    end

    def component_hash(c)
      { id: id(c), aircraft_id: id(c.aircraft_id), parent_component_id: id(c.parent_component_id), component_type_id: id(c.component_type_id),
        manufacturer: c.manufacturer, model: c.model, serial_number: c.serial_number, install_location: c.install_location,
        notes: c.notes, status: c.status, date_in_service: c.date_in_service&.iso8601, hours_in_service: dec(c.hours_in_service),
        hours_since_overhaul: dec(c.hours_since_overhaul), overhaul_date: c.overhaul_date&.iso8601, tbo_hours: c.tbo_hours,
        tbo_days: c.tbo_days, inspection_hours: c.inspection_hours, inspection_days: c.inspection_days,
        replacement_hours: c.replacement_hours, replacement_days: c.replacement_days, tbo_critical: c.tbo_critical,
        on_condition: c.on_condition, inspection_critical: c.inspection_critical, replacement_critical: c.replacement_critical }
    end

    def logbook_hash(e)
      { id: id(e), aircraft_id: id(e.aircraft_id), log_type: e.log_type, date: e.date&.iso8601, text: e.text,
        signoff_person: e.signoff_person, signoff_location: e.signoff_location, log_image_id: id(e.document_id),
        aircraft_hours_at_entry: dec(e.aircraft_hours_at_entry), component_hours: {}, entry_type: e.entry_type,
        page_number: e.page_number, components: [], related_documents: [] }
    end

    def squawk_hash(s)
      paths = s.attachments.map { file(_1, "health/squawks") }
      { id: id(s), aircraft_id: id(s.aircraft_id), component_id: id(s.component_id), priority: s.priority,
        issue_reported: s.issue_reported, attachment: paths.first, created_at: s.created_at&.iso8601,
        reported_by_display: s.reported_by&.display_name, resolved: s.resolved, notes: s.notes, logbook_entries: [],
        attachments: paths, resolved_at: s.resolved_at&.iso8601 }
    end

    def inspection_type_hash(t, component_ids)
      { id: id(t), name: t.name, recurring: t.recurring, required: t.required, recurring_hours: dec(t.recurring_hours),
        recurring_days: t.recurring_days, recurring_months: t.recurring_months,
        applicable_aircraft: t.aircraft_ids.include?(@aircraft.id) ? [ id(@aircraft) ] : [],
        applicable_component: (t.component_ids & component_ids).map { id(_1) } }
    end

    def ad_hash(ad, component_ids)
      { id: id(ad), name: ad.name, short_description: ad.short_description, required_action: ad.required_action,
        compliance_type: ad.compliance_type, trigger_condition: ad.trigger_condition, recurring: ad.recurring,
        recurring_hours: dec(ad.recurring_hours), recurring_months: ad.recurring_months, recurring_days: ad.recurring_days,
        bulletin_type: ad.bulletin_type, mandatory: ad.mandatory,
        document_id: (id(ad.document_id) if ad.document&.aircraft_id == @aircraft.id), on_inspection_type: [],
        applicable_aircraft: ad.aircraft_ids.include?(@aircraft.id) ? [ id(@aircraft) ] : [],
        applicable_component: (ad.component_ids & component_ids).map { id(_1) },
        effective_date: ad.effective_date&.iso8601, supersedes: ad.supersedes, superseded_by: ad.superseded_by,
        docket_number: ad.docket_number, applicable_models: ad.applicable_models, product_type: ad.product_type,
        document_url: ad.document_url }
    end

    def oil_hash(o)
      { id: id(o), aircraft_id: id(o.aircraft_id), component_id: id(o.component_id), sample_date: o.sample_date&.iso8601,
        analysis_date: o.analysis_date&.iso8601, lab: o.lab.to_s, lab_number: o.sample_number.to_s, oil_type: o.oil_type.to_s,
        oil_hours: dec(o.oil_hours), engine_hours: dec(o.engine_hours), oil_added_quarts: dec(o.oil_added),
        elements_ppm: o.elements, oil_properties: o.oil_properties.presence, lab_comments: o.lab_comments.to_s,
        status: o.status, notes: o.notes.to_s, excluded_from_averages: o.excluded_from_averages,
        filter_hours: dec(o.filter_hours), element_averages: o.element_averages, report: file(o.report, "oil_reports") }
    end

    def flight_hash(f)
      { id: id(f), aircraft_id: id(f.aircraft_id), date: f.date&.iso8601, tach_time: dec(f.tach_time), tach_out: dec(f.tach_out),
        tach_in: dec(f.tach_in), hobbs_time: dec(f.hobbs_time), hobbs_out: dec(f.hobbs_out), hobbs_in: dec(f.hobbs_in),
        departure_location: f.departure_location.to_s, destination_location: f.destination_location.to_s, route: f.route.to_s,
        oil_added: dec(f.oil_added), oil_added_type: f.oil_added_type.to_s, oil_level_after: dec(f.oil_level_after),
        fuel_added: dec(f.fuel_added), fuel_added_type: f.fuel_added_type.to_s, fuel_level_after: dec(f.fuel_level_after),
        track_log: file(f.track_log, "track_logs"), notes: f.notes.to_s, created_at: f.created_at&.iso8601,
        engine_data: file(f.engine_data, "engine_data"), pilot_display: f.user&.display_name }
    end
  end
end

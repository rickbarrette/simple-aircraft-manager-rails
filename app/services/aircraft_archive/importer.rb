require "zip"

module AircraftArchive
  # Reads a .sam.zip (from this app or the original Simple Aircraft Manager) and
  # creates the aircraft with all its records and files.
  #
  #   preview = AircraftArchive::Importer.check(path)         # fast safety checks
  #   AircraftArchive::Importer.new(path, owner:, tail_number:).run
  #
  # Archive IDs are only used to link records inside the archive; everything
  # gets new IDs here. Component types, inspection types and ADs are shared
  # across aircraft, so existing ones with the same name are reused.
  #
  # No single transaction wraps the import (SQLite would block other writers for
  # its whole length). If it fails part-way, the new aircraft and anything else
  # it created are removed again.
  class Importer
    Preview = Struct.new(:tail_number, :make, :model, :source, :exported_at, :counts, keyword_init: true)
    RECORD_SECTIONS = %w[components document_collections documents document_images logbook_entries squawks inspection_types
                         inspection_records ads ad_compliances consumable_records major_records notes oil_analysis_reports flight_logs].freeze

    # Safety and format checks that don't import anything. Raises Error.
    def self.check(path)
      manifest = with_zip(path) { |zip| validate_zip(zip) }
      a = manifest["aircraft"]
      Preview.new(tail_number: a["tail_number"], make: a["make"], model: a["model"], source: manifest["source_instance"].presence,
                  exported_at: (Time.zone.parse(manifest["exported_at"].to_s) rescue nil),
                  counts: RECORD_SECTIONS.to_h { [ _1, Array(manifest[_1]).size ] })
    end

    # Opens the archive. A records package (Access & Sharing) carries the
    # .sam.zip inside it, so that inner archive is opened instead.
    def self.with_zip(path, &)
      Zip.validate_entry_sizes = true # a lying size header raises instead of inflating forever
      Zip::File.open(path) do |zip|
        inner = nested_archive(zip)
        next yield(zip) unless inner
        raise Error, "The archive inside the records package is too large." if inner.size > ARCHIVE_MAX_BYTES
        Tempfile.create([ "sam-inner", ".zip" ], binmode: true) do |tmp|
          inner.get_input_stream { |io| IO.copy_stream(io, tmp) }
          tmp.flush
          Zip::File.open(tmp.path, &)
        end
      end
    rescue Zip::Error => e
      raise Error, "Not a valid .sam.zip archive (#{e.message})"
    end

    # The single *.sam.zip entry of a records package (no manifest of its own).
    def self.nested_archive(zip)
      return if zip.find_entry("manifest.json") || root_prefix(zip).present?
      candidates = zip.entries.reject { _1.name.start_with?("__MACOSX/") }.select { _1.name.match?(%r{\A([^/]+/)?[^/]+\.sam\.zip\z}) }
      candidates.first if candidates.one?
    end

    # "" normally; "folder/" when everything sits in one folder, as when a
    # browser unzipped the download and the folder was zipped again (Finder's
    # Compress adds that folder, and a __MACOSX folder that's ignored).
    def self.root_prefix(zip)
      return "" if zip.find_entry("manifest.json")
      folders = zip.entries.map(&:name).reject { _1.start_with?("__MACOSX/") }.grep(%r{\A[^/]+/manifest\.json\z})
      folders.one? ? folders.first.delete_suffix("manifest.json") : ""
    end

    def self.validate_zip(zip)
      uncompressed = compressed = 0
      zip.each do |entry|
        raise Error, "The archive contains a link (#{entry.name}), which isn't allowed." if entry.symlink?
        raise Error, "The archive contains an unsafe path: #{entry.name}" unless safe_name?(entry.name)
        uncompressed += entry.size
        compressed += entry.compressed_size
        raise Error, "The archive is too large once unpacked." if uncompressed > ARCHIVE_MAX_BYTES
      end
      raise Error, "The archive is compressed suspiciously well (over #{MAX_RATIO}:1)." if compressed.positive? && uncompressed / compressed > MAX_RATIO

      entry = zip.find_entry("#{root_prefix(zip)}manifest.json") or raise Error, "The archive has no manifest.json. Is it a .sam.zip export?"
      raise Error, "manifest.json is too large." if entry.size > MANIFEST_MAX_BYTES
      manifest = begin
        JSON.parse(entry.get_input_stream.read.force_encoding("UTF-8"))
      rescue JSON::ParserError => e
        raise Error, "manifest.json couldn't be read (#{e.message.truncate(120)})"
      end
      raise Error, "manifest.json isn't a JSON object." unless manifest.is_a?(Hash)

      version = manifest["schema_version"]
      unless version.is_a?(Integer) && version.between?(1, SCHEMA_VERSION)
        raise Error, "Unsupported archive version #{version.inspect} (this app reads versions 1–#{SCHEMA_VERSION})."
      end
      required = TOP_LEVEL_KEYS - OPTIONAL_KEYS - (version < 2 ? %w[flight_logs] : [])
      missing = required - manifest.keys
      raise Error, "manifest.json is missing #{missing.to_sentence}." if missing.any?
      raise Error, "manifest.json has no aircraft tail number." unless manifest["aircraft"].is_a?(Hash) && manifest["aircraft"]["tail_number"].present?
      RECORD_SECTIONS.each { |key| raise Error, "manifest.json #{key} must be a list." unless manifest[key].nil? || manifest[key].is_a?(Array) }
      manifest
    end

    # Relative, no "..", valid UTF-8 (zip entry names arrive as raw bytes).
    def self.safe_name?(name)
      name = name.to_s.dup.force_encoding(Encoding::UTF_8)
      return false if name.blank? || !name.valid_encoding? || name.start_with?("/", "\\") || name.match?(/\A[A-Za-z]:/)
      name.unicode_normalize(:nfc).tr("\\", "/").split("/").exclude?("..")
    end

    attr_reader :counts, :warnings, :aircraft

    def initialize(path, owner:, tail_number: nil, progress: nil)
      @path = path
      @owner = owner
      @tail_number = tail_number
      @progress = progress || ->(_counts) { }
      @counts = Hash.new(0)
      @warnings = []
      @map = Hash.new { |h, k| h[k] = {} } # section → archive id → new record id
      @created_blobs = []
      @created_shared = [] # component types / inspection types / ADs made by this import
    end

    def run
      self.class.with_zip(@path) do |zip|
        @zip = zip
        @manifest = self.class.validate_zip(zip)
        @root = self.class.root_prefix(zip)
        import_all
      end
      { aircraft: @aircraft, counts: @counts, warnings: @warnings }
    rescue StandardError
      clean_up
      raise
    end

    private

    def m(key) = Array(@manifest[key]).select { _1.is_a?(Hash) }

    # {component id => value} as exported (keys may be strings or numbers).
    def hash_value(hash, key) = hash.is_a?(Hash) ? (hash[key.to_s] || hash[key]) : nil

    def import_all
      import_aircraft
      import_component_types
      import_components
      import_documents
      import_logbook
      import_squawks
      import_inspections
      import_ads
      import_consumables
      import_major_records
      import_notes
      import_oil_analyses
      import_flight_logs
      @aircraft.roles.find_or_create_by!(user: @owner, role: "owner") if @owner
      @aircraft.log_event!("aircraft", "Aircraft imported from a .sam.zip archive",
                           notes: [ @manifest["source_instance"].presence && "Source: #{@manifest['source_instance']}", summary ].compact.join(". "),
                           user: @owner)
    end

    def summary = @counts.select { _2.positive? }.map { |k, n| "#{n} #{k.tr('_', ' ')}" }.join(", ")

    def tick(section, n = 1)
      @counts[section] += n
      @progress.call(@counts) if (@counts.values.sum % 25).zero?
    end

    # ---- records ----

    def import_aircraft
      a = @manifest["aircraft"]
      @aircraft = Aircraft.new(
        tail_number: (@tail_number.presence || a["tail_number"]).to_s.strip.upcase,
        make: a["make"].to_s, model: a["model"].to_s, serial_number: a["serial_number"].to_s, description: a["description"].to_s,
        purchased: date(a["purchased"]), status: Aircraft::STATUSES.key?(a["status"]) ? a["status"] : "AVAILABLE",
        time_basis: Aircraft::TIME_BASES.key?(a["time_basis"]) ? a["time_basis"] : "tach",
        electronic_records_since: date(a["electronic_records_since"]),
        loading_stations: a["loading_stations"].is_a?(Hash) ? a["loading_stations"] : nil,
        cg_envelope: a["cg_envelope"].is_a?(Array) ? a["cg_envelope"] : nil, ad_watch_terms: a["ad_watch_terms"].to_s.first(500).presence,
        tach_time: num(a["tach_time"] || a["flight_time"]) || 0, tach_time_offset: num(a["tach_time_offset"]) || 0,
        hobbs_time: num(a["hobbs_time"]) || 0, hobbs_time_offset: num(a["hobbs_time_offset"]) || 0,
        icao_type: a["icao_type"].to_s.upcase.presence&.then { _1.match?(/\A[A-Z0-9]{1,4}\z/) ? _1 : nil }
      )
      feature = m("features").find { _1["feature"] == "airworthiness_enforcement" }
      @aircraft.airworthiness_enforcement = feature["enabled"] if feature && !feature["enabled"].nil? && @aircraft.has_attribute?(:airworthiness_enforcement)
      @aircraft.save!(validate: false)
      attach(@aircraft.picture, a["picture"], "aircraft picture") unless a["_missing"]
    end

    def import_component_types
      m("component_types").each do |data|
        name = data["name"].to_s.strip
        next if name.blank?
        type = ComponentType.where("LOWER(name) = ?", name.downcase).first ||
               ComponentType.create!(name: name, consumable: data["consumable"] == true).tap { @created_shared << _1 }
        @map[:component_type][data["id"].to_s] = type.id
      end
    end

    def import_components
      by_id = m("components").index_by { _1["id"].to_s }
      ordered = []
      visit = lambda do |data, seen = []|
        return if ordered.include?(data) || seen.include?(data)
        parent = by_id[data["parent_component_id"].to_s]
        visit.(parent, seen + [ data ]) if parent
        ordered << data
      end
      by_id.each_value { visit.(_1) }

      ordered.each do |data|
        type_id = @map[:component_type][data["component_type_id"].to_s]
        next warn("Component #{data['manufacturer']} #{data['model']}: unknown component type, skipped.") unless type_id
        c = @aircraft.components.new(
          component_type_id: type_id, parent_component_id: @map[:component][data["parent_component_id"].to_s],
          manufacturer: data["manufacturer"].to_s, model: data["model"].to_s, serial_number: data["serial_number"].to_s,
          install_location: data["install_location"].to_s, notes: data["notes"].to_s, expires_on: date(data["expires_on"]),
          status: Component::STATUSES.key?(data["status"]) ? data["status"] : "SPARE",
          date_in_service: date(data["date_in_service"]) || Date.new(1900, 1, 1), hours_in_service: num(data["hours_in_service"]) || 0,
          hours_since_overhaul: num(data["hours_since_overhaul"]) || 0, overhaul_date: date(data["overhaul_date"]),
          **data.slice(*%w[tbo_hours tbo_days inspection_hours inspection_days replacement_hours replacement_days
                                  tbo_months inspection_months replacement_months]).symbolize_keys,
          **data.slice(*%w[tbo_critical on_condition inspection_critical replacement_critical]).transform_values { _1 == true }.symbolize_keys
        )
        c.save!(validate: false)
        @map[:component][data["id"].to_s] = c.id
        tick("components")
      end
    end

    def import_documents
      m("document_collections").each do |data|
        c = @aircraft.document_collections.new(name: data["name"].to_s.presence || "Untitled", description: data["description"].to_s,
                                               visibility: visibility(data["visibility"]) || "private", starred: data["starred"] == true)
        c.save!(validate: false)
        @map[:collection][data["id"].to_s] = c.id
      end
      documents = {}
      m("documents").each do |data|
        d = @aircraft.documents.new(name: data["name"].to_s.presence || "Untitled", description: data["description"].to_s,
                                    doc_type: data["doc_type"].presence, visibility: visibility(data["visibility"]),
                                    document_collection_id: @map[:collection][data["collection_id"].to_s],
                                    expires_on: date(data["expires_on"]), legacy_record: data["legacy_record"] == true)
        d.doc_type = "OTHER" unless Document::TYPES.key?(d.doc_type)
        d.save!(validate: false)
        @map[:document][data["id"].to_s] = d.id
        documents[d.id] = d
        tick("documents")
      end
      m("document_images").each do |data|
        document = documents[@map[:document][data["document_id"].to_s]] or next
        next if data["_missing"]
        tick("document_pages") if attach(document.pages, data["image"], "document #{document.name}")
      end
    end

    def import_logbook
      m("logbook_entries").each do |data|
        e = @aircraft.logbook_entries.new(
          log_type: LogbookEntry::LOG_TYPES.key?(data["log_type"]) ? data["log_type"] : "AC",
          entry_type: LogbookEntry::ENTRY_TYPES.key?(data["entry_type"]) ? data["entry_type"] : LogbookEntry::ENTRY_TYPES.keys.first,
          date: date(data["date"]) || Date.new(1900, 1, 1), text: data["text"].to_s.presence || "—",
          signoff_person: data["signoff_person"], signoff_location: data["signoff_location"],
          signoff_certificate_type: LogbookEntry::CERTIFICATE_TYPES.key?(data["signoff_certificate_type"]) ? data["signoff_certificate_type"] : nil,
          signoff_certificate_number: data["signoff_certificate_number"].to_s.presence,
          inspection_result: LogbookEntry::INSPECTION_RESULTS.key?(data["inspection_result"]) ? data["inspection_result"] : nil,
          verified: data["verified"] != false,
          transcription_confidence: %w[high medium low].include?(data["transcription_confidence"]) ? data["transcription_confidence"] : nil,
          aircraft_hours_at_entry: num(data["aircraft_hours_at_entry"]), page_number: data["page_number"],
          document_id: @map[:document][data["log_image_id"].to_s]
        )
        # The first component is the entry's; the rest are its sub-components, each with its times.
        refs = Array(data["components"]).select { @map[:component][_1.to_s] }
        if (ref = refs.first)
          e.component_id = @map[:component][ref.to_s]
          e.component_hours_at_entry = num(hash_value(data["component_hours"], ref))
          e.component_since_overhaul_at_entry = num(hash_value(data["component_since_overhaul"], ref))
        end
        refs.drop(1).uniq.each do |r|
          e.parts.build(component_id: @map[:component][r.to_s], hours_at_entry: num(hash_value(data["component_hours"], r)),
                        since_overhaul_at_entry: num(hash_value(data["component_since_overhaul"], r)))
        end
        e.superseded_at = time(data["superseded_at"])
        e.save!(validate: false)
        @map[:logbook][data["id"].to_s] = e.id
        (@supersedes ||= []) << [ e.id, data["supersedes_id"].to_s ] if data["supersedes_id"].present?
        import_signature(e, data["signature"]) if data["signature"].is_a?(Hash)

        tick("logbook_entries")
      end
    end

    def import_squawks
      m("squawks").each do |data|
        s = @aircraft.squawks.new(
          priority: Squawk::PRIORITIES.key?(data["priority"]) ? data["priority"] : 3, issue_reported: data["issue_reported"].to_s.presence || "—",
          notes: data["notes"], resolved: data["resolved"] == true, component_id: @map[:component][data["component_id"].to_s],
          created_at: time(data["created_at"]) || Time.current
        )
        s.resolved_at = time(data["resolved_at"]) || (s.created_at if s.resolved)
        s.save!(validate: false)
        paths = Array(data["attachments"]).presence || [ data["attachment"] ].compact
        paths.each { attach(s.attachments, _1, "squawk “#{s.issue_reported.truncate(40)}”") } unless data["_missing"]
        tick("squawks")
      end
    end

    def import_inspections
      m("inspection_types").each do |data|
        name = data["name"].to_s.strip
        next if name.blank?
        type = InspectionType.where("LOWER(name) = ?", name.downcase).first
        if type
          warn("Inspection type “#{name}” already existed here and was reused.") if type.recurring != (data["recurring"] == true)
        else
          effect = InspectionType::EFFECTS.key?(data["effect"]) ? data["effect"] : (data["required"] == false ? "advisory" : "grounds")
          type = InspectionType.new(name: name, recurring: data["recurring"] == true, effect: effect,
                                    required: effect != "advisory", hours_tolerance: num(data["hours_tolerance"]) || 0,
                                    recurring_hours: num(data["recurring_hours"]), recurring_days: data["recurring_days"],
                                    recurring_months: data["recurring_months"])
          type.save!(validate: false)
          @created_shared << type
        end
        type.aircraft << @aircraft if Array(data["applicable_aircraft"]).any? && !type.aircraft.include?(@aircraft)
        components(data["applicable_component"]).each { |c| type.components << c unless type.components.include?(c) }
        @map[:inspection_type][data["id"].to_s] = type.id
        (@satisfies ||= []) << [ type, data["satisfies"].to_s ] if data["satisfies"].present?
      end
      Array(@satisfies).each do |type, ref|
        target = @map[:inspection_type][ref]
        type.update_column(:satisfies_id, target) if target && type.satisfies_id.nil? && target != type.id
      end
      m("inspection_records").each do |data|
        type_id = @map[:inspection_type][data["inspection_type_id"].to_s]
        next warn("An inspection record from #{data['date']} has no inspection type and was skipped.") unless type_id
        r = @aircraft.inspection_records.new(
          inspection_type_id: type_id, date: date(data["date"]) || Date.new(1900, 1, 1), aircraft_hours: num(data["aircraft_hours"]),
          logbook_entry_id: @map[:logbook][data["logbook_entry_id"].to_s], notes: data["notes"],
          component_id: @map[:component][Array(data["component"]).first.to_s]
        )
        r.save!(validate: false)
        @map[:inspection_record][data["id"].to_s] = r.id
        tick("inspection_records")
      end
    end

    def import_ads
      m("ads").each do |data|
        name = data["name"].to_s.strip
        next if name.blank?
        ad = AirworthinessDirective.where("LOWER(name) = ?", name.downcase).first
        unless ad
          ad = AirworthinessDirective.new(
            name: name, short_description: data["short_description"].to_s, required_action: data["required_action"].to_s,
            compliance_type: AirworthinessDirective::COMPLIANCE_TYPES.key?(data["compliance_type"]) ? data["compliance_type"] : "standard",
            trigger_condition: data["trigger_condition"].to_s, recurring: data["recurring"] == true,
            recurring_hours: num(data["recurring_hours"]), recurring_months: data["recurring_months"], recurring_days: data["recurring_days"],
            bulletin_type: AirworthinessDirective::BULLETIN_TYPES.key?(data["bulletin_type"]) ? data["bulletin_type"] : "ad",
            mandatory: data["mandatory"] != false, document_id: @map[:document][data["document_id"].to_s],
            effective_date: date(data["effective_date"]), supersedes: data["supersedes"], superseded_by: data["superseded_by"],
            docket_number: data["docket_number"], applicable_models: data["applicable_models"], product_type: data["product_type"],
            document_url: data["document_url"]
          )
          ad.save!(validate: false)
          @created_shared << ad
        end
        ad.aircraft << @aircraft if Array(data["applicable_aircraft"]).any? && !ad.aircraft.include?(@aircraft)
        components(data["applicable_component"]).each { |c| ad.components << c unless ad.components.include?(c) }
        @map[:ad][data["id"].to_s] = ad.id
        tick("ads")
      end
      m("ad_compliances").each do |data|
        ad_id = @map[:ad][data["ad_id"].to_s] or next
        c = @aircraft.ad_compliances.new(
          airworthiness_directive_id: ad_id, date_complied: date(data["date_complied"]) || Date.new(1900, 1, 1),
          compliance_notes: data["compliance_notes"].to_s, permanent: data["permanent"] == true,
          compliance_method: AdCompliance::METHODS.key?(data["compliance_method"]) ? data["compliance_method"] : nil,
          ad_revision: data["ad_revision"].to_s.presence,
          next_due_at_time: num(data["next_due_at_time"]) || 0, aircraft_hours_at_compliance: num(data["aircraft_hours_at_compliance"]),
          logbook_entry_id: @map[:logbook][data["logbook_entry_id"].to_s],
          inspection_record_id: @map[:inspection_record][data["inspection_record_id"].to_s],
          component_id: @map[:component][data["component_id"].to_s], not_applicable: data["not_applicable"] == true
        )
        c.apply_method # older archives have only the permanent / not-applicable flags
        c.save!(validate: false)
        tick("ad_compliances")
      end
    end

    def import_consumables
      @consumable_flight_links = {}
      m("consumable_records").each do |data|
        next unless ConsumableRecord::TYPES.key?(data["record_type"])
        r = @aircraft.consumable_records.new(
          record_type: data["record_type"], date: date(data["date"]) || Date.new(1900, 1, 1), quantity_added: num(data["quantity_added"]) || 0,
          level_after: num(data["level_after"]), consumable_type: data["consumable_type"].to_s, flight_hours: num(data["flight_hours"]) || 0,
          notes: data["notes"].to_s, excluded_from_averages: data["excluded_from_averages"] == true
        )
        r.save!(validate: false)
        @consumable_flight_links[r.id] = data["flight_log_id"].to_s if data["flight_log_id"]
        tick("consumable_records")
      end
    end

    def import_major_records
      m("major_records").each do |data|
        r = @aircraft.major_records.new(
          record_type: MajorRecord::RECORD_TYPES.key?(data["record_type"]) ? data["record_type"] : "repair",
          title: data["title"].to_s.presence || "—", description: data["description"].to_s, date_performed: date(data["date_performed"]),
          performed_by: data["performed_by"].to_s, component_id: @map[:component][data["component_id"].to_s],
          form_337_document_id: @map[:document][data["form_337_document_id"].to_s], stc_number: data["stc_number"].to_s,
          stc_holder: data["stc_holder"].to_s, stc_document_id: @map[:document][data["stc_document_id"].to_s],
          logbook_entry_id: @map[:logbook][data["logbook_entry_id"].to_s], aircraft_hours: num(data["aircraft_hours"]),
          notes: data["notes"].to_s, has_ica: data["has_ica"] == true, ica_notes: data["ica_notes"],
          ica_inspection_type_id: @map[:inspection_type][data["ica_inspection_type_id"].to_s]
        )
        r.save!(validate: false)
        (@map[:major_record] ||= {})[data["id"].to_s] = r.id
        tick("major_records")
      end
      import_weight_balance
      Array(@supersedes).each do |entry_id, ref|
        target = @map[:logbook][ref]
        LogbookEntry.where(id: entry_id).update_all(supersedes_id: target) if target
      end
    end

    def import_signature(entry, sig)
      kind = LogbookEntry::CERTIFICATE_TYPES.key?(sig["certificate_kind"]) ? sig["certificate_kind"] : "OTHER"
      EntrySignature.new(
        logbook_entry: entry, signer_name: sig["signer_name"].to_s.presence || "Unknown", signer_email: sig["signer_email"],
        certificate_kind: kind, certificate_number: sig["certificate_number"].to_s.presence || "unknown",
        statement: sig["statement"].to_s.presence || "—", signed_at: time(sig["signed_at"]) || Time.current,
        content_digest: sig["content_digest"].to_s.presence || "unknown", content_snapshot: sig["content_snapshot"].to_s.presence || "{}",
        auth_method: EntrySignature::AUTH_METHODS.key?(sig["auth_method"]) ? sig["auth_method"] : "imported",
        origin: sig["origin"].to_s.presence || "another system"
      ).save!(validate: false)
    end

    def import_weight_balance
      m("weight_balance_records").each do |data|
        w = @aircraft.weight_balance_records.new(
          date: date(data["date"]) || Date.new(1900, 1, 1), empty_weight: num(data["empty_weight"]) || 0, empty_arm: num(data["empty_arm"]) || 0,
          max_gross_weight: num(data["max_gross_weight"]), reason: data["reason"].to_s.presence, notes: data["notes"].to_s.presence,
          major_record_id: (@map[:major_record] || {})[data["major_record_id"].to_s], document_id: @map[:document][data["document_id"].to_s]
        )
        w.save!(validate: false)
        tick("weight_balance_records")
      end
    end

    def import_notes
      m("notes").each do |data|
        at = time(data["added_timestamp"]) || Time.current
        n = @aircraft.notes.new(text: data["text"].to_s.presence || "—", public: data["public"] == true, created_at: at,
                                edited_at: time(data["edited_at"]))
        n.text = "#{n.text}\n\n— #{data['added_by_display']}" if data["added_by_display"].present?
        n.save!(validate: false)
        tick("notes")
      end
    end

    def import_oil_analyses
      m("oil_analysis_reports").each do |data|
        o = @aircraft.oil_analyses.new(
          component_id: @map[:component][data["component_id"].to_s], sample_date: date(data["sample_date"]) || Date.new(1900, 1, 1),
          analysis_date: date(data["analysis_date"]), lab: data["lab"].presence, sample_number: data["lab_number"].presence,
          oil_type: data["oil_type"].presence, oil_hours: num(data["oil_hours"]), engine_hours: num(data["engine_hours"]),
          filter_hours: num(data["filter_hours"]), oil_added: num(data["oil_added_quarts"]),
          elements: data["elements_ppm"].is_a?(Hash) ? data["elements_ppm"] : {},
          element_averages: data["element_averages"].is_a?(Hash) ? data["element_averages"] : {},
          oil_properties: data["oil_properties"].is_a?(Hash) ? data["oil_properties"] : {},
          lab_comments: data["lab_comments"].presence, notes: data["notes"].presence,
          status: OilAnalysis::STATUSES.key?(data["status"]) ? data["status"] : nil,
          excluded_from_averages: data["excluded_from_averages"] == true
        )
        o.save!(validate: false)
        attach(o.report, data["report"], "oil analysis #{o.sample_date}") if data["report"]
        tick("oil_analyses")
      end
    end

    def import_flight_logs
      m("flight_logs").each do |data|
        f = @aircraft.flight_logs.new(
          date: date(data["date"]) || Date.new(1900, 1, 1), tach_time: num(data["tach_time"]) || 0, tach_out: num(data["tach_out"]),
          tach_in: num(data["tach_in"]), hobbs_time: num(data["hobbs_time"]), hobbs_out: num(data["hobbs_out"]),
          hobbs_in: num(data["hobbs_in"]), departure_location: data["departure_location"].to_s,
          destination_location: data["destination_location"].to_s, route: data["route"].to_s, oil_added: num(data["oil_added"]),
          oil_added_type: data["oil_added_type"].to_s, oil_level_after: num(data["oil_level_after"]), fuel_added: num(data["fuel_added"]),
          fuel_added_type: data["fuel_added_type"].to_s, fuel_level_after: num(data["fuel_level_after"]), notes: data["notes"].to_s,
          created_at: time(data["created_at"]) || Time.current
        )
        f.save!(validate: false)
        @map[:flight_log][data["id"].to_s] = f.id
        attach(f.track_log, data["track_log"], "flight #{f.date} track log") if data["track_log"] && !data["_missing"]
        attach(f.engine_data, data["engine_data"], "flight #{f.date} engine data") if data["engine_data"]
        tick("flight_logs")
      end
      (@consumable_flight_links || {}).each do |record_id, archive_flight_id|
        flight_id = @map[:flight_log][archive_flight_id] or next
        ConsumableRecord.where(id: record_id).update_all(flight_log_id: flight_id)
      end
    end

    # ---- files ----

    # Copy one archive file into storage and attach it. Problems with a single
    # file become warnings; the record is kept without it.
    def attach(target, archive_path, what)
      return false if archive_path.blank?
      blob = upload(archive_path.to_s)
      target.attach(blob)
      true
    rescue Error => e
      warn("#{what.upcase_first}: #{e.message}")
      false
    end

    def upload(archive_path)
      raise Error, "unsafe file path #{archive_path}" unless self.class.safe_name?(archive_path)
      entry = @zip.find_entry("#{@root}#{archive_path}") or raise Error, "file #{File.basename(archive_path)} isn't in the archive"
      raise Error, "#{File.basename(archive_path)} is too large" if entry.size > FILE_MAX_BYTES
      ext = AircraftArchive.extension(archive_path)
      raise Error, "#{File.basename(archive_path)} isn't an allowed file type" unless EXTENSIONS.include?(ext)

      Tempfile.create([ "sam-import", ".#{ext}" ], binmode: true) do |tmp|
        entry.get_input_stream { |input| IO.copy_stream(input, tmp) }
        tmp.rewind
        head = tmp.read(16).to_s
        raise Error, "#{File.basename(archive_path)} doesn't contain what its name says (.#{ext})" unless AircraftArchive.content_matches?(head, ext)
        tmp.rewind
        ActiveStorage::Blob.create_and_upload!(io: tmp, filename: File.basename(archive_path)).tap { @created_blobs << _1 }
      end
    end

    # ---- helpers ----

    def warn(message)
      @warnings << message
      nil
    end

    def components(ids) = Array(ids).filter_map { @map[:component][_1.to_s] }.then { Component.where(id: _1) }

    def visibility(value) = DocumentCollection::VISIBILITIES.key?(value) ? value : nil

    def date(value)
      Date.iso8601(value.to_s[0, 10]) if value.present?
    rescue Date::Error
      nil
    end

    def time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def num(value)
      return nil if value.blank?
      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    # Undo a failed import: the aircraft (and its records, via dependent
    # destroys), shared records only this import created, and uploaded files.
    def clean_up
      @aircraft&.destroy if @aircraft&.persisted?
      @created_shared.reverse_each { |record| record.destroy if record.class.exists?(record.id) }
      @created_blobs.each { |blob| blob.purge if ActiveStorage::Blob.exists?(blob.id) }
    rescue StandardError => e
      Rails.logger.error("[aircraft import] clean-up failed: #{e.class}: #{e.message}")
    end
  end
end

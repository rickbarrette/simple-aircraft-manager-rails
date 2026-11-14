# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_13_010000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ad_alerts", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.string "fr_document_number", null: false
    t.string "ad_number"
    t.string "amendment"
    t.string "title"
    t.text "abstract"
    t.date "publication_date"
    t.date "effective_on"
    t.string "html_url"
    t.string "matched_term"
    t.string "status", default: "new", null: false
    t.integer "airworthiness_directive_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "component_id"
    t.index ["aircraft_id", "fr_document_number"], name: "index_ad_alerts_on_aircraft_id_and_fr_document_number", unique: true
    t.index ["aircraft_id"], name: "index_ad_alerts_on_aircraft_id"
    t.index ["airworthiness_directive_id"], name: "index_ad_alerts_on_airworthiness_directive_id"
    t.index ["component_id"], name: "index_ad_alerts_on_component_id"
  end

  create_table "ad_compliances", force: :cascade do |t|
    t.integer "airworthiness_directive_id", null: false
    t.integer "aircraft_id"
    t.integer "component_id"
    t.integer "logbook_entry_id"
    t.integer "inspection_record_id"
    t.date "date_complied", null: false
    t.text "compliance_notes", null: false
    t.boolean "permanent", default: false, null: false
    t.decimal "next_due_at_time", precision: 8, scale: 1, default: "0.0", null: false
    t.decimal "aircraft_hours_at_compliance", precision: 8, scale: 1
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "not_applicable", default: false, null: false
    t.string "compliance_method"
    t.string "ad_revision"
    t.index ["aircraft_id"], name: "index_ad_compliances_on_aircraft_id"
    t.index ["airworthiness_directive_id"], name: "index_ad_compliances_on_airworthiness_directive_id"
    t.index ["component_id"], name: "index_ad_compliances_on_component_id"
    t.index ["inspection_record_id"], name: "index_ad_compliances_on_inspection_record_id"
    t.index ["logbook_entry_id"], name: "index_ad_compliances_on_logbook_entry_id"
  end

  create_table "air_trail_airports", force: :cascade do |t|
    t.integer "air_trail_connection_id", null: false
    t.string "code", null: false
    t.integer "remote_id"
    t.string "remote_icao"
    t.boolean "manual", default: false, null: false
    t.datetime "looked_up_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["air_trail_connection_id", "code"], name: "idx_air_trail_airports_unique", unique: true
    t.index ["air_trail_connection_id"], name: "index_air_trail_airports_on_air_trail_connection_id"
  end

  create_table "air_trail_connections", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "base_url", null: false
    t.text "api_key", null: false
    t.boolean "enabled", default: true, null: false
    t.string "remote_user_id"
    t.string "remote_username"
    t.string "status"
    t.text "last_error"
    t.datetime "checked_at"
    t.datetime "backfilled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_air_trail_connections_on_user_id", unique: true
  end

  create_table "air_trail_syncs", force: :cascade do |t|
    t.integer "air_trail_connection_id", null: false
    t.integer "flight_log_id", null: false
    t.integer "remote_id"
    t.string "payload_digest"
    t.string "status", default: "pending", null: false
    t.text "last_error"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["air_trail_connection_id", "flight_log_id"], name: "idx_air_trail_syncs_unique", unique: true
    t.index ["air_trail_connection_id"], name: "index_air_trail_syncs_on_air_trail_connection_id"
    t.index ["flight_log_id"], name: "index_air_trail_syncs_on_flight_log_id"
  end

  create_table "aircraft", force: :cascade do |t|
    t.string "tail_number", null: false
    t.string "make"
    t.string "model"
    t.string "serial_number"
    t.text "description"
    t.date "purchased"
    t.string "status", default: "AVAILABLE", null: false
    t.decimal "tach_time", precision: 8, scale: 1, default: "0.0", null: false
    t.decimal "tach_time_offset", precision: 8, scale: 1, default: "0.0", null: false
    t.decimal "hobbs_time", precision: 8, scale: 1, default: "0.0", null: false
    t.decimal "hobbs_time_offset", precision: 8, scale: 1, default: "0.0", null: false
    t.boolean "airworthiness_enforcement", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "icao_type"
    t.string "time_basis", default: "tach", null: false
    t.json "loading_stations"
    t.json "cg_envelope"
    t.string "ad_watch_terms"
    t.datetime "ad_watch_checked_at"
    t.date "electronic_records_since"
    t.json "notified_issue_keys", default: [], null: false
  end

  create_table "aircraft_airworthiness_directives", id: false, force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "airworthiness_directive_id", null: false
    t.index ["aircraft_id", "airworthiness_directive_id"], name: "idx_aircraft_ads", unique: true
  end

  create_table "aircraft_events", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "user_id"
    t.string "category", null: false
    t.string "event_name", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.index ["aircraft_id", "created_at"], name: "index_aircraft_events_on_aircraft_id_and_created_at"
    t.index ["aircraft_id"], name: "index_aircraft_events_on_aircraft_id"
    t.index ["user_id"], name: "index_aircraft_events_on_user_id"
  end

  create_table "aircraft_imports", force: :cascade do |t|
    t.integer "user_id"
    t.integer "aircraft_id"
    t.string "status", default: "queued", null: false
    t.string "filename"
    t.string "tail_number"
    t.string "source"
    t.json "counts", default: {}, null: false
    t.json "warnings", default: [], null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_aircraft_imports_on_aircraft_id"
    t.index ["user_id"], name: "index_aircraft_imports_on_user_id"
  end

  create_table "aircraft_inspection_types", id: false, force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "inspection_type_id", null: false
    t.index ["aircraft_id", "inspection_type_id"], name: "idx_aircraft_inspection_types", unique: true
  end

  create_table "aircraft_notes", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "user_id"
    t.text "text", null: false
    t.boolean "public", default: false, null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_aircraft_notes_on_aircraft_id"
    t.index ["user_id"], name: "index_aircraft_notes_on_user_id"
  end

  create_table "aircraft_roles", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "user_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id", "user_id"], name: "index_aircraft_roles_on_aircraft_id_and_user_id", unique: true
    t.index ["aircraft_id"], name: "index_aircraft_roles_on_aircraft_id"
    t.index ["user_id"], name: "index_aircraft_roles_on_user_id"
  end

  create_table "airport_updates", force: :cascade do |t|
    t.string "status", default: "queued", null: false
    t.string "source_url"
    t.integer "created_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "removed_count", default: 0, null: false
    t.text "error"
    t.integer "requested_by_id"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requested_by_id"], name: "index_airport_updates_on_requested_by_id"
  end

  create_table "airports", force: :cascade do |t|
    t.string "ident", null: false
    t.string "airtrail_code", null: false
    t.string "gps_code"
    t.string "local_code"
    t.string "iata"
    t.string "name", null: false
    t.string "kind"
    t.string "municipality"
    t.string "region"
    t.string "country"
    t.float "latitude"
    t.float "longitude"
    t.integer "elevation_ft"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "custom", default: false, null: false
    t.index ["airtrail_code"], name: "index_airports_on_airtrail_code"
    t.index ["custom"], name: "index_airports_on_custom"
    t.index ["gps_code"], name: "index_airports_on_gps_code"
    t.index ["iata"], name: "index_airports_on_iata"
    t.index ["ident"], name: "index_airports_on_ident", unique: true
    t.index ["local_code"], name: "index_airports_on_local_code"
  end

  create_table "airworthiness_directives", force: :cascade do |t|
    t.string "name", null: false
    t.string "short_description", null: false
    t.text "required_action"
    t.string "compliance_type", default: "standard", null: false
    t.text "trigger_condition"
    t.boolean "recurring", default: false, null: false
    t.decimal "recurring_hours", precision: 8, scale: 1, default: "0.0", null: false
    t.integer "recurring_months", default: 0, null: false
    t.integer "recurring_days", default: 0, null: false
    t.string "bulletin_type", default: "ad", null: false
    t.boolean "mandatory", default: true, null: false
    t.integer "document_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "effective_date"
    t.string "supersedes"
    t.string "superseded_by"
    t.string "docket_number"
    t.text "applicable_models"
    t.string "product_type"
    t.string "document_url"
    t.index ["document_id"], name: "index_airworthiness_directives_on_document_id"
  end

  create_table "airworthiness_directives_components", id: false, force: :cascade do |t|
    t.integer "component_id", null: false
    t.integer "airworthiness_directive_id", null: false
    t.index ["component_id", "airworthiness_directive_id"], name: "idx_component_ads", unique: true
  end

  create_table "app_revisions", force: :cascade do |t|
    t.string "revision", null: false
    t.datetime "built_at"
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.string "version"
    t.index ["revision"], name: "index_app_revisions_on_revision", unique: true
  end

  create_table "audit_runs", force: :cascade do |t|
    t.integer "performed_by_id"
    t.datetime "performed_at", null: false
    t.boolean "passed", null: false
    t.json "results", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["performed_by_id"], name: "index_audit_runs_on_performed_by_id"
  end

  create_table "backup_runs", force: :cascade do |t|
    t.boolean "ok", null: false
    t.string "path"
    t.bigint "bytes"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "component_types", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "consumable", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_component_types_on_name", unique: true
  end

  create_table "components", force: :cascade do |t|
    t.integer "aircraft_id"
    t.integer "parent_component_id"
    t.integer "component_type_id", null: false
    t.string "manufacturer", null: false
    t.string "model", null: false
    t.string "serial_number"
    t.string "install_location"
    t.text "notes"
    t.string "status", default: "SPARE", null: false
    t.date "date_in_service", null: false
    t.decimal "hours_in_service", precision: 8, scale: 1, default: "0.0", null: false
    t.decimal "hours_since_overhaul", precision: 8, scale: 1, default: "0.0", null: false
    t.date "overhaul_date"
    t.integer "tbo_hours"
    t.integer "tbo_days"
    t.integer "replacement_hours"
    t.integer "replacement_days"
    t.boolean "tbo_critical", default: true, null: false
    t.boolean "on_condition", default: false, null: false
    t.boolean "replacement_critical", default: false, null: false
    t.boolean "replacement_from_install", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "expires_on"
    t.string "overhaul_kind"
    t.integer "replacement_months"
    t.integer "tbo_months"
    t.index ["aircraft_id"], name: "index_components_on_aircraft_id"
    t.index ["component_type_id"], name: "index_components_on_component_type_id"
    t.index ["parent_component_id"], name: "index_components_on_parent_component_id"
  end

  create_table "components_inspection_types", id: false, force: :cascade do |t|
    t.integer "component_id", null: false
    t.integer "inspection_type_id", null: false
    t.index ["component_id", "inspection_type_id"], name: "idx_component_inspection_types", unique: true
  end

  create_table "consumable_records", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "flight_log_id"
    t.string "record_type", null: false
    t.date "date", null: false
    t.decimal "quantity_added", precision: 6, scale: 2, null: false
    t.decimal "level_after", precision: 6, scale: 2
    t.string "consumable_type"
    t.decimal "flight_hours", precision: 8, scale: 1, null: false
    t.text "notes"
    t.boolean "excluded_from_averages", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id", "record_type", "flight_hours"], name: "idx_on_aircraft_id_record_type_flight_hours_2c5ed6828c"
    t.index ["aircraft_id"], name: "index_consumable_records_on_aircraft_id"
    t.index ["flight_log_id"], name: "index_consumable_records_on_flight_log_id"
  end

  create_table "document_collections", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "visibility", default: "private", null: false
    t.boolean "starred", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_document_collections_on_aircraft_id"
  end

  create_table "documents", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "document_collection_id"
    t.string "doc_type", default: "OTHER", null: false
    t.string "name", null: false
    t.text "description"
    t.string "visibility"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "expires_on"
    t.boolean "legacy_record", default: false, null: false
    t.text "pages_text"
    t.string "pages_text_method"
    t.string "pages_text_source"
    t.datetime "pages_text_at"
    t.index ["aircraft_id"], name: "index_documents_on_aircraft_id"
    t.index ["document_collection_id"], name: "index_documents_on_document_collection_id"
  end

  create_table "drs_imports", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "user_id"
    t.string "filename"
    t.json "models_covered"
    t.integer "ad_count", default: 0, null: false
    t.integer "tracked", default: 0, null: false
    t.integer "not_applicable", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_drs_imports_on_aircraft_id"
    t.index ["user_id"], name: "index_drs_imports_on_user_id"
  end

  create_table "entry_signatures", force: :cascade do |t|
    t.integer "logbook_entry_id", null: false
    t.integer "user_id"
    t.string "signer_name", null: false
    t.string "signer_email"
    t.string "certificate_kind", null: false
    t.string "certificate_number", null: false
    t.text "statement", null: false
    t.datetime "signed_at", null: false
    t.string "content_digest", null: false
    t.text "content_snapshot", null: false
    t.string "seal"
    t.string "auth_method", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.string "origin"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["logbook_entry_id"], name: "index_entry_signatures_on_logbook_entry_id"
    t.index ["logbook_entry_id"], name: "index_entry_signatures_one_per_entry", unique: true
    t.index ["user_id"], name: "index_entry_signatures_on_user_id"
  end

  create_table "flight_logs", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "user_id"
    t.date "date", null: false
    t.decimal "tach_time", precision: 6, scale: 1, null: false
    t.decimal "tach_out", precision: 8, scale: 1
    t.decimal "tach_in", precision: 8, scale: 1
    t.decimal "hobbs_time", precision: 6, scale: 1
    t.decimal "hobbs_out", precision: 8, scale: 1
    t.decimal "hobbs_in", precision: 8, scale: 1
    t.string "departure_location"
    t.string "destination_location"
    t.text "route"
    t.decimal "oil_added", precision: 6, scale: 2
    t.string "oil_added_type"
    t.decimal "oil_level_after", precision: 6, scale: 2
    t.decimal "fuel_added", precision: 8, scale: 2
    t.string "fuel_added_type"
    t.decimal "fuel_level_after", precision: 8, scale: 2
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "client_key"
    t.index ["aircraft_id", "client_key"], name: "index_flight_logs_on_aircraft_id_and_client_key", unique: true
    t.index ["aircraft_id"], name: "index_flight_logs_on_aircraft_id"
    t.index ["user_id"], name: "index_flight_logs_on_user_id"
  end

  create_table "inspection_records", force: :cascade do |t|
    t.integer "inspection_type_id", null: false
    t.integer "aircraft_id"
    t.integer "component_id"
    t.integer "logbook_entry_id"
    t.date "date", null: false
    t.decimal "aircraft_hours", precision: 8, scale: 1
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_inspection_records_on_aircraft_id"
    t.index ["component_id"], name: "index_inspection_records_on_component_id"
    t.index ["inspection_type_id"], name: "index_inspection_records_on_inspection_type_id"
    t.index ["logbook_entry_id"], name: "index_inspection_records_on_logbook_entry_id"
  end

  create_table "inspection_types", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "recurring", default: false, null: false
    t.boolean "required", default: true, null: false
    t.decimal "recurring_hours", precision: 8, scale: 1, default: "0.0", null: false
    t.integer "recurring_days", default: 0, null: false
    t.integer "recurring_months", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "effect", default: "grounds", null: false
    t.decimal "hours_tolerance", precision: 6, scale: 1, default: "0.0", null: false
    t.integer "satisfies_id"
    t.index ["satisfies_id"], name: "index_inspection_types_on_satisfies_id"
  end

  create_table "integrity_checks", force: :cascade do |t|
    t.boolean "ok", null: false
    t.integer "versions_checked", default: 0, null: false
    t.integer "signatures_checked", default: 0, null: false
    t.json "problems"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "logbook_entries", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "document_id"
    t.string "log_type", default: "AC", null: false
    t.string "entry_type", default: "MAINTENANCE", null: false
    t.date "date", null: false
    t.text "text", null: false
    t.text "signoff_person"
    t.string "signoff_location"
    t.decimal "aircraft_hours_at_entry", precision: 8, scale: 1
    t.integer "page_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "signoff_certificate_type"
    t.string "signoff_certificate_number"
    t.string "inspection_result"
    t.boolean "verified", default: true, null: false
    t.string "transcription_confidence"
    t.integer "component_id"
    t.decimal "component_hours_at_entry", precision: 8, scale: 1
    t.decimal "component_since_overhaul_at_entry", precision: 8, scale: 1
    t.integer "supersedes_id"
    t.datetime "superseded_at"
    t.index ["aircraft_id"], name: "index_logbook_entries_on_aircraft_id"
    t.index ["component_id"], name: "index_logbook_entries_on_component_id"
    t.index ["document_id"], name: "index_logbook_entries_on_document_id"
    t.index ["supersedes_id"], name: "index_logbook_entries_on_supersedes_id"
  end

  create_table "logbook_entry_parts", force: :cascade do |t|
    t.integer "logbook_entry_id", null: false
    t.integer "component_id", null: false
    t.decimal "hours_at_entry", precision: 8, scale: 1
    t.decimal "since_overhaul_at_entry", precision: 8, scale: 1
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["component_id"], name: "index_logbook_entry_parts_on_component_id"
    t.index ["logbook_entry_id", "component_id"], name: "index_logbook_entry_parts_on_logbook_entry_id_and_component_id", unique: true
    t.index ["logbook_entry_id"], name: "index_logbook_entry_parts_on_logbook_entry_id"
  end

  create_table "logbook_imports", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "user_id"
    t.integer "document_id"
    t.string "status", default: "queued", null: false
    t.boolean "transcribe", default: true, null: false
    t.string "log_type"
    t.string "model"
    t.integer "pages_total", default: 0, null: false
    t.integer "pages_done", default: 0, null: false
    t.integer "entries_created", default: 0, null: false
    t.json "warnings", default: [], null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_logbook_imports_on_aircraft_id"
    t.index ["document_id"], name: "index_logbook_imports_on_document_id"
    t.index ["user_id"], name: "index_logbook_imports_on_user_id"
  end

  create_table "logbook_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "reference"
    t.text "text", null: false
    t.string "entry_type", default: "MAINTENANCE", null: false
    t.string "log_type"
    t.string "certificate_type"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "major_records", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "component_id"
    t.integer "form_337_document_id"
    t.integer "stc_document_id"
    t.integer "logbook_entry_id"
    t.string "record_type", null: false
    t.string "title", null: false
    t.text "description"
    t.date "date_performed", null: false
    t.string "performed_by"
    t.string "stc_number"
    t.string "stc_holder"
    t.decimal "aircraft_hours", precision: 8, scale: 1
    t.boolean "has_ica", default: false, null: false
    t.text "ica_notes"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ica_inspection_type_id"
    t.index ["aircraft_id"], name: "index_major_records_on_aircraft_id"
    t.index ["component_id"], name: "index_major_records_on_component_id"
    t.index ["form_337_document_id"], name: "index_major_records_on_form_337_document_id"
    t.index ["ica_inspection_type_id"], name: "index_major_records_on_ica_inspection_type_id"
    t.index ["logbook_entry_id"], name: "index_major_records_on_logbook_entry_id"
    t.index ["stc_document_id"], name: "index_major_records_on_stc_document_id"
  end

  create_table "offsite_connections", force: :cascade do |t|
    t.string "provider", default: "google_drive", null: false
    t.string "client_id"
    t.text "client_secret"
    t.text "refresh_token"
    t.string "account_email"
    t.string "folder_id"
    t.string "database_folder_id"
    t.string "files_folder_id"
    t.integer "connected_by_id"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connected_by_id"], name: "index_offsite_connections_on_connected_by_id"
  end

  create_table "offsite_files", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "drive_file_id", null: false
    t.bigint "bytes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_offsite_files_on_blob_id", unique: true
  end

  create_table "offsite_runs", force: :cascade do |t|
    t.string "kind", null: false
    t.boolean "ok", null: false
    t.text "message"
    t.bigint "bytes"
    t.integer "files_uploaded", default: 0, null: false
    t.json "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "created_at"], name: "index_offsite_runs_on_kind_and_created_at"
  end

  create_table "oil_analyses", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "component_id"
    t.date "sample_date", null: false
    t.date "analysis_date"
    t.string "lab"
    t.string "sample_number"
    t.decimal "engine_hours", precision: 8, scale: 1
    t.decimal "oil_hours", precision: 6, scale: 1
    t.decimal "filter_hours", precision: 6, scale: 1
    t.decimal "oil_added", precision: 6, scale: 2
    t.string "status"
    t.text "lab_comments"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "elements", default: {}, null: false
    t.json "element_averages", default: {}, null: false
    t.json "oil_properties", default: {}, null: false
    t.string "oil_type"
    t.boolean "excluded_from_averages", default: false, null: false
    t.index ["aircraft_id", "sample_date"], name: "index_oil_analyses_on_aircraft_id_and_sample_date"
    t.index ["aircraft_id"], name: "index_oil_analyses_on_aircraft_id"
    t.index ["component_id"], name: "index_oil_analyses_on_component_id"
  end

  create_table "procedures_revisions", force: :cascade do |t|
    t.integer "number", null: false
    t.integer "adopted_by_id"
    t.datetime "adopted_at", null: false
    t.text "summary"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["adopted_by_id"], name: "index_procedures_revisions_on_adopted_by_id"
    t.index ["number"], name: "index_procedures_revisions_on_number", unique: true
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "record_versions", force: :cascade do |t|
    t.integer "aircraft_id"
    t.string "item_type", null: false
    t.integer "item_id", null: false
    t.string "event", null: false
    t.integer "user_id"
    t.string "ip_address"
    t.text "payload", null: false
    t.string "prev_hash"
    t.string "chain_hash", null: false
    t.datetime "created_at", null: false
    t.index ["aircraft_id"], name: "index_record_versions_on_aircraft_id"
    t.index ["item_type", "item_id"], name: "index_record_versions_on_item_type_and_item_id"
  end

  create_table "recordkeeping_policies", force: :cascade do |t|
    t.string "operator_name"
    t.string "responsible_name"
    t.string "responsible_title"
    t.text "hosting_description"
    t.text "offsite_backup_description"
    t.integer "audit_interval_months", default: 6, null: false
    t.integer "audit_sample_size", default: 5, null: false
    t.text "additional_procedures"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "share_tokens", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "created_by_id"
    t.string "token", null: false
    t.string "label"
    t.string "privilege", default: "status", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_share_tokens_on_aircraft_id"
    t.index ["created_by_id"], name: "index_share_tokens_on_created_by_id"
    t.index ["token"], name: "index_share_tokens_on_token", unique: true
  end

  create_table "signing_invitations", force: :cascade do |t|
    t.integer "logbook_entry_id", null: false
    t.integer "invited_by_id"
    t.integer "user_id"
    t.string "email", null: false
    t.string "token_digest", null: false
    t.text "message"
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_signing_invitations_on_invited_by_id"
    t.index ["logbook_entry_id"], name: "index_signing_invitations_on_logbook_entry_id"
    t.index ["token_digest"], name: "index_signing_invitations_on_token_digest", unique: true
    t.index ["user_id"], name: "index_signing_invitations_on_user_id"
  end

  create_table "squawks", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.integer "component_id"
    t.integer "reported_by_id"
    t.integer "priority", default: 0, null: false
    t.text "issue_reported"
    t.text "notes"
    t.boolean "resolved", default: false, null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deferred_at"
    t.string "deferred_by_name"
    t.string "deferred_by_role"
    t.string "deferral_action"
    t.text "deferral_notes"
    t.integer "logbook_entry_id"
    t.string "client_key"
    t.index ["aircraft_id", "client_key"], name: "index_squawks_on_aircraft_id_and_client_key", unique: true
    t.index ["aircraft_id"], name: "index_squawks_on_aircraft_id"
    t.index ["component_id"], name: "index_squawks_on_component_id"
    t.index ["logbook_entry_id"], name: "index_squawks_on_logbook_entry_id"
    t.index ["reported_by_id"], name: "index_squawks_on_reported_by_id"
  end

  create_table "user_certificates", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "kind", null: false
    t.string "number", null: false
    t.date "expires_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_certificates_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.boolean "admin", default: false, null: false
    t.string "sso_uid"
    t.datetime "last_signed_in_at"
    t.boolean "reminder_emails", default: true, null: false
    t.datetime "disabled_at"
    t.integer "failed_sign_ins", default: 0, null: false
    t.datetime "locked_until"
    t.text "otp_secret"
    t.datetime "otp_enabled_at"
    t.integer "otp_last_used_at"
    t.json "otp_recovery_codes"
    t.string "calendar_token"
    t.index ["calendar_token"], name: "index_users_on_calendar_token", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["sso_uid"], name: "index_users_on_sso_uid", unique: true
  end

  create_table "weight_balance_records", force: :cascade do |t|
    t.integer "aircraft_id", null: false
    t.date "date", null: false
    t.decimal "empty_weight", precision: 8, scale: 1, null: false
    t.decimal "empty_arm", precision: 7, scale: 2, null: false
    t.decimal "max_gross_weight", precision: 8, scale: 1
    t.string "reason"
    t.text "notes"
    t.integer "major_record_id"
    t.integer "document_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aircraft_id"], name: "index_weight_balance_records_on_aircraft_id"
    t.index ["document_id"], name: "index_weight_balance_records_on_document_id"
    t.index ["major_record_id"], name: "index_weight_balance_records_on_major_record_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ad_alerts", "aircraft"
  add_foreign_key "ad_alerts", "airworthiness_directives", on_delete: :nullify
  add_foreign_key "ad_alerts", "components", on_delete: :nullify
  add_foreign_key "ad_compliances", "aircraft"
  add_foreign_key "ad_compliances", "airworthiness_directives"
  add_foreign_key "ad_compliances", "components"
  add_foreign_key "ad_compliances", "inspection_records", on_delete: :nullify
  add_foreign_key "ad_compliances", "logbook_entries", on_delete: :nullify
  add_foreign_key "air_trail_airports", "air_trail_connections"
  add_foreign_key "air_trail_connections", "users"
  add_foreign_key "air_trail_syncs", "air_trail_connections"
  add_foreign_key "air_trail_syncs", "flight_logs"
  add_foreign_key "aircraft_events", "aircraft"
  add_foreign_key "aircraft_events", "users", on_delete: :nullify
  add_foreign_key "aircraft_imports", "aircraft", on_delete: :nullify
  add_foreign_key "aircraft_imports", "users"
  add_foreign_key "aircraft_notes", "aircraft"
  add_foreign_key "aircraft_notes", "users", on_delete: :nullify
  add_foreign_key "aircraft_roles", "aircraft"
  add_foreign_key "aircraft_roles", "users"
  add_foreign_key "airport_updates", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "airworthiness_directives", "documents", on_delete: :nullify
  add_foreign_key "audit_runs", "users", column: "performed_by_id", on_delete: :nullify
  add_foreign_key "components", "aircraft"
  add_foreign_key "components", "component_types"
  add_foreign_key "components", "components", column: "parent_component_id"
  add_foreign_key "consumable_records", "aircraft"
  add_foreign_key "consumable_records", "flight_logs", on_delete: :nullify
  add_foreign_key "document_collections", "aircraft"
  add_foreign_key "documents", "aircraft"
  add_foreign_key "documents", "document_collections"
  add_foreign_key "drs_imports", "aircraft", on_delete: :cascade
  add_foreign_key "drs_imports", "users", on_delete: :nullify
  add_foreign_key "entry_signatures", "logbook_entries"
  add_foreign_key "entry_signatures", "users", on_delete: :nullify
  add_foreign_key "flight_logs", "aircraft"
  add_foreign_key "flight_logs", "users", on_delete: :nullify
  add_foreign_key "inspection_records", "aircraft"
  add_foreign_key "inspection_records", "components"
  add_foreign_key "inspection_records", "inspection_types"
  add_foreign_key "inspection_records", "logbook_entries", on_delete: :nullify
  add_foreign_key "inspection_types", "inspection_types", column: "satisfies_id", on_delete: :nullify
  add_foreign_key "logbook_entries", "aircraft"
  add_foreign_key "logbook_entries", "components", on_delete: :nullify
  add_foreign_key "logbook_entries", "documents", on_delete: :nullify
  add_foreign_key "logbook_entries", "logbook_entries", column: "supersedes_id", on_delete: :nullify
  add_foreign_key "logbook_entry_parts", "components", on_delete: :cascade
  add_foreign_key "logbook_entry_parts", "logbook_entries", on_delete: :cascade
  add_foreign_key "logbook_imports", "aircraft"
  add_foreign_key "logbook_imports", "documents", on_delete: :nullify
  add_foreign_key "logbook_imports", "users", on_delete: :nullify
  add_foreign_key "major_records", "aircraft"
  add_foreign_key "major_records", "components", on_delete: :nullify
  add_foreign_key "major_records", "documents", column: "form_337_document_id", on_delete: :nullify
  add_foreign_key "major_records", "documents", column: "stc_document_id", on_delete: :nullify
  add_foreign_key "major_records", "inspection_types", column: "ica_inspection_type_id", on_delete: :nullify
  add_foreign_key "major_records", "logbook_entries", on_delete: :nullify
  add_foreign_key "offsite_connections", "users", column: "connected_by_id"
  add_foreign_key "oil_analyses", "aircraft"
  add_foreign_key "oil_analyses", "components"
  add_foreign_key "procedures_revisions", "users", column: "adopted_by_id", on_delete: :nullify
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "share_tokens", "aircraft"
  add_foreign_key "share_tokens", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "signing_invitations", "logbook_entries", on_delete: :cascade
  add_foreign_key "signing_invitations", "users", column: "invited_by_id", on_delete: :nullify
  add_foreign_key "signing_invitations", "users", on_delete: :nullify
  add_foreign_key "squawks", "aircraft"
  add_foreign_key "squawks", "components", on_delete: :nullify
  add_foreign_key "squawks", "logbook_entries", on_delete: :nullify
  add_foreign_key "squawks", "users", column: "reported_by_id", on_delete: :nullify
  add_foreign_key "user_certificates", "users"
  add_foreign_key "weight_balance_records", "aircraft"
  add_foreign_key "weight_balance_records", "documents", on_delete: :nullify
  add_foreign_key "weight_balance_records", "major_records", on_delete: :nullify
end

# - logbook_entries.verified: AI-transcribed entries start unverified until
#   someone checks them against the scan
# - major_records.ica_inspection_type: the recurring inspection an STC's
#   Instructions for Continued Airworthiness call for
# - weight_balance_records + aircraft loading setup: weight & balance history
#   and a loading calculator
# - ad_alerts + aircraft.ad_watch_terms: newly published ADs that may apply
class AddGroupFourRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :logbook_entries, :verified, :boolean, null: false, default: true
    add_column :logbook_entries, :transcription_confidence, :string
    add_reference :major_records, :ica_inspection_type, foreign_key: { to_table: :inspection_types, on_delete: :nullify }

    create_table :weight_balance_records do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :empty_weight, precision: 8, scale: 1, null: false
      t.decimal :empty_arm, precision: 7, scale: 2, null: false
      t.decimal :max_gross_weight, precision: 8, scale: 1
      t.string :reason
      t.text :notes
      t.references :major_record, foreign_key: { on_delete: :nullify }
      t.references :document, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    add_column :aircraft, :loading_stations, :json
    add_column :aircraft, :cg_envelope, :json
    add_column :aircraft, :ad_watch_terms, :string
    add_column :aircraft, :ad_watch_checked_at, :datetime

    create_table :ad_alerts do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.string :fr_document_number, null: false
      t.string :ad_number
      t.string :amendment
      t.string :title
      t.text :abstract
      t.date :publication_date
      t.date :effective_on
      t.string :html_url
      t.string :matched_term
      t.string :status, null: false, default: "new"
      t.references :airworthiness_directive, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :ad_alerts, %i[aircraft_id fr_document_number], unique: true
  end
end

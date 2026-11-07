# Scanned logbook pages uploaded as a document, optionally transcribed into
# logbook entries by Claude (LogbookTranscriptionJob).
class CreateLogbookImports < ActiveRecord::Migration[8.1]
  def change
    create_table :logbook_imports do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :document, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "queued" # queued, running, done, failed
      t.boolean :transcribe, null: false, default: true
      t.string :log_type               # force every entry to this log; nil = Claude decides
      t.string :model
      t.integer :pages_total, null: false, default: 0
      t.integer :pages_done, null: false, default: 0
      t.integer :entries_created, null: false, default: 0
      t.json :warnings, null: false, default: []
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end

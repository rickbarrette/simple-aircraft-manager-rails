# One upload of an aircraft archive (.sam.zip) and the background job importing it.
class CreateAircraftImports < ActiveRecord::Migration[8.1]
  def change
    create_table :aircraft_imports do |t|
      t.references :user, foreign_key: true
      t.references :aircraft, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "queued" # queued, running, done, failed
      t.string :filename
      t.string :tail_number          # the tail the aircraft will be created with
      t.string :source               # where the archive came from (manifest source_instance)
      t.json :counts, null: false, default: {}
      t.json :warnings, null: false, default: []
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end

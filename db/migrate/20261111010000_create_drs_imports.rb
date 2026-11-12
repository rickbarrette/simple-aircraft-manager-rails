class CreateDrsImports < ActiveRecord::Migration[8.1]
  def change
    # Each FAA DRS import: when, by whom, and which of the aircraft's models
    # the file covered (the baseline the weekly new-AD search builds on).
    create_table :drs_imports do |t|
      t.references :aircraft, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :filename
      t.json :models_covered
      t.integer :ad_count, null: false, default: 0
      t.integer :tracked, null: false, default: 0
      t.integer :not_applicable, null: false, default: 0
      t.timestamps
    end
  end
end

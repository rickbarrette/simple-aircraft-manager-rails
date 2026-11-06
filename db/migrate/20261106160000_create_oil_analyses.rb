class CreateOilAnalyses < ActiveRecord::Migration[8.1]
  ELEMENTS = %i[iron copper nickel chromium silver magnesium aluminum lead silicon titanium tin molybdenum].freeze

  def change
    # One lab report (spectrographic oil analysis) per oil sample.
    create_table :oil_analyses do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :component, foreign_key: true # the engine sampled
      t.date :sample_date, null: false
      t.date :analysis_date
      t.string :lab
      t.string :sample_number
      t.decimal :engine_hours, precision: 8, scale: 1 # TSN/TSO at sampling
      t.decimal :oil_hours, precision: 6, scale: 1
      t.decimal :filter_hours, precision: 6, scale: 1
      t.decimal :oil_added, precision: 6, scale: 2   # quarts added since last change
      t.string :status, null: false, default: "normal"
      t.text :lab_comments
      t.text :notes
      # Wear metals and contaminants, ppm; *_avg is the lab's average for similar engines.
      ELEMENTS.each do |el|
        t.decimal el, precision: 8, scale: 1
        t.decimal :"#{el}_avg", precision: 8, scale: 1
      end
      t.timestamps
    end
    add_index :oil_analyses, %i[aircraft_id sample_date]
  end
end

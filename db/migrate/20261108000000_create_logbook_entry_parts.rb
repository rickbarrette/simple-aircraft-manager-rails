# Sub-components a logbook entry also covers (e.g. the oil filter on the
# engine), with their times at the entry.
class CreateLogbookEntryParts < ActiveRecord::Migration[8.1]
  def change
    create_table :logbook_entry_parts do |t|
      t.references :logbook_entry, null: false, foreign_key: { on_delete: :cascade }
      t.references :component, null: false, foreign_key: { on_delete: :cascade }
      t.decimal :hours_at_entry, precision: 8, scale: 1
      t.decimal :since_overhaul_at_entry, precision: 8, scale: 1
      t.timestamps
    end
    add_index :logbook_entry_parts, %i[logbook_entry_id component_id], unique: true
  end
end

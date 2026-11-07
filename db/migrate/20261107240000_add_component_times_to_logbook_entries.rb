# Engine and propeller log entries record which component they're for and
# its times at the entry (total, and since overhaul), as printed in the log.
class AddComponentTimesToLogbookEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :logbook_entries, :component, foreign_key: { on_delete: :nullify }
    add_column :logbook_entries, :component_hours_at_entry, :decimal, precision: 8, scale: 1
    add_column :logbook_entries, :component_since_overhaul_at_entry, :decimal, precision: 8, scale: 1
    add_column :components, :overhaul_kind, :string
  end
end

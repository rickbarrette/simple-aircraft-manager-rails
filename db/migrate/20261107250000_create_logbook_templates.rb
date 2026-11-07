# Logbook entry templates admins can add and edit (the built-in preventive
# maintenance set is added on first use; see LogbookTemplate.ensure_defaults!).
class CreateLogbookTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :logbook_templates do |t|
      t.string :name, null: false
      t.string :reference
      t.text :text, null: false
      t.string :entry_type, null: false, default: "MAINTENANCE"
      t.string :log_type
      t.string :certificate_type
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end

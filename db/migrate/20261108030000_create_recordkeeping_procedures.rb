# AC 120-78B 2.2.11 / 3.2.8: the procedures document (generated from the
# system and a few owner-supplied facts, adopted as numbered revisions) and
# the QC audits it calls for (3.2.8.5).
class CreateRecordkeepingProcedures < ActiveRecord::Migration[8.1]
  def change
    create_table :recordkeeping_policies do |t|
      t.string :operator_name
      t.string :responsible_name
      t.string :responsible_title
      t.text :hosting_description
      t.text :offsite_backup_description
      t.integer :audit_interval_months, null: false, default: 6
      t.integer :audit_sample_size, null: false, default: 5
      t.text :additional_procedures
      t.timestamps
    end

    create_table :procedures_revisions do |t|
      t.integer :number, null: false
      t.references :adopted_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :adopted_at, null: false
      t.text :summary
      t.text :content, null: false
      t.timestamps
    end
    add_index :procedures_revisions, :number, unique: true

    create_table :audit_runs do |t|
      t.references :performed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :performed_at, null: false
      t.boolean :passed, null: false
      t.json :results, null: false
      t.text :notes
      t.timestamps
    end
  end
end

class CreateAircraftDomain < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :name, :string
    add_column :users, :admin, :boolean, null: false, default: false

    create_table :aircraft do |t|
      t.string :tail_number, null: false
      t.string :make
      t.string :model
      t.string :serial_number
      t.text :description
      t.date :purchased
      t.string :status, null: false, default: "AVAILABLE"
      t.decimal :tach_time, precision: 8, scale: 1, null: false, default: 0
      t.decimal :tach_time_offset, precision: 8, scale: 1, null: false, default: 0
      t.decimal :hobbs_time, precision: 8, scale: 1, null: false, default: 0
      t.decimal :hobbs_time_offset, precision: 8, scale: 1, null: false, default: 0
      t.boolean :airworthiness_enforcement, null: false, default: false
      t.timestamps
    end

    create_table :aircraft_roles do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :aircraft_roles, [ :aircraft_id, :user_id ], unique: true

    create_table :aircraft_notes do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.text :text, null: false
      t.boolean :public, null: false, default: false
      t.datetime :edited_at
      t.timestamps
    end

    create_table :aircraft_events do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :category, null: false
      t.string :event_name, null: false
      t.text :notes
      t.datetime :created_at, null: false
    end
    add_index :aircraft_events, [ :aircraft_id, :created_at ]

    create_table :share_tokens do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :token, null: false
      t.string :label
      t.string :privilege, null: false, default: "status"
      t.datetime :expires_at
      t.timestamps
    end
    add_index :share_tokens, :token, unique: true

    create_table :component_types do |t|
      t.string :name, null: false
      t.boolean :consumable, null: false, default: false
      t.timestamps
    end
    add_index :component_types, :name, unique: true

    create_table :components do |t|
      t.references :aircraft, foreign_key: true
      t.references :parent_component, foreign_key: { to_table: :components }
      t.references :component_type, null: false, foreign_key: true
      t.string :manufacturer, null: false
      t.string :model, null: false
      t.string :serial_number
      t.string :install_location
      t.text :notes
      t.string :status, null: false, default: "SPARE"
      t.date :date_in_service, null: false
      t.decimal :hours_in_service, precision: 8, scale: 1, null: false, default: 0
      t.decimal :hours_since_overhaul, precision: 8, scale: 1, null: false, default: 0
      t.date :overhaul_date
      t.integer :tbo_hours
      t.integer :tbo_days
      t.integer :inspection_hours
      t.integer :inspection_days
      t.integer :replacement_hours
      t.integer :replacement_days
      t.boolean :tbo_critical, null: false, default: true
      t.boolean :on_condition, null: false, default: false
      t.boolean :inspection_critical, null: false, default: true
      t.boolean :replacement_critical, null: false, default: false
      t.timestamps
    end

    create_table :document_collections do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :visibility, null: false, default: "private"
      t.boolean :starred, null: false, default: false
      t.timestamps
    end

    create_table :documents do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :document_collection, foreign_key: true
      t.string :doc_type, null: false, default: "OTHER"
      t.string :name, null: false
      t.text :description
      # nil = inherit from collection (or private when uncollected)
      t.string :visibility
      t.timestamps
    end

    create_table :logbook_entries do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :document, foreign_key: { on_delete: :nullify } # scanned page(s)
      t.string :log_type, null: false, default: "AC"
      t.string :entry_type, null: false, default: "MAINTENANCE"
      t.date :date, null: false
      t.text :text, null: false
      t.text :signoff_person
      t.string :signoff_location
      t.decimal :aircraft_hours_at_entry, precision: 8, scale: 1
      t.integer :page_number
      t.timestamps
    end

    create_table :squawks do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :component, foreign_key: { on_delete: :nullify }
      t.references :reported_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :priority, null: false, default: 0
      t.text :issue_reported
      t.text :notes
      t.boolean :resolved, null: false, default: false
      t.datetime :resolved_at
      t.timestamps
    end

    create_table :inspection_types do |t|
      t.string :name, null: false
      t.boolean :recurring, null: false, default: false
      t.boolean :required, null: false, default: true
      t.decimal :recurring_hours, precision: 8, scale: 1, null: false, default: 0
      t.integer :recurring_days, null: false, default: 0
      t.integer :recurring_months, null: false, default: 0
      t.timestamps
    end
    create_join_table :aircraft, :inspection_types do |t|
      t.index [ :aircraft_id, :inspection_type_id ], unique: true, name: "idx_aircraft_inspection_types"
    end
    create_join_table :components, :inspection_types do |t|
      t.index [ :component_id, :inspection_type_id ], unique: true, name: "idx_component_inspection_types"
    end

    create_table :inspection_records do |t|
      t.references :inspection_type, null: false, foreign_key: true
      t.references :aircraft, foreign_key: true
      t.references :component, foreign_key: true
      t.references :logbook_entry, foreign_key: { on_delete: :nullify }
      t.date :date, null: false
      t.decimal :aircraft_hours, precision: 8, scale: 1
      t.text :notes
      t.timestamps
    end

    create_table :airworthiness_directives do |t|
      t.string :name, null: false
      t.string :short_description, null: false
      t.text :required_action
      t.string :compliance_type, null: false, default: "standard"
      t.text :trigger_condition
      t.boolean :recurring, null: false, default: false
      t.decimal :recurring_hours, precision: 8, scale: 1, null: false, default: 0
      t.integer :recurring_months, null: false, default: 0
      t.integer :recurring_days, null: false, default: 0
      t.string :bulletin_type, null: false, default: "ad"
      t.boolean :mandatory, null: false, default: true
      t.references :document, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    create_join_table :aircraft, :airworthiness_directives do |t|
      t.index [ :aircraft_id, :airworthiness_directive_id ], unique: true, name: "idx_aircraft_ads"
    end
    create_join_table :components, :airworthiness_directives do |t|
      t.index [ :component_id, :airworthiness_directive_id ], unique: true, name: "idx_component_ads"
    end

    create_table :ad_compliances do |t|
      t.references :airworthiness_directive, null: false, foreign_key: true
      t.references :aircraft, foreign_key: true
      t.references :component, foreign_key: true
      t.references :logbook_entry, foreign_key: { on_delete: :nullify }
      t.references :inspection_record, foreign_key: { on_delete: :nullify }
      t.date :date_complied, null: false
      t.text :compliance_notes, null: false
      t.boolean :permanent, null: false, default: false
      t.decimal :next_due_at_time, precision: 8, scale: 1, null: false, default: 0
      t.decimal :aircraft_hours_at_compliance, precision: 8, scale: 1
      t.timestamps
    end

    create_table :major_records do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :component, foreign_key: { on_delete: :nullify }
      t.references :form_337_document, foreign_key: { to_table: :documents, on_delete: :nullify }
      t.references :stc_document, foreign_key: { to_table: :documents, on_delete: :nullify }
      t.references :logbook_entry, foreign_key: { on_delete: :nullify }
      t.string :record_type, null: false
      t.string :title, null: false
      t.text :description
      t.date :date_performed, null: false
      t.string :performed_by
      t.string :stc_number
      t.string :stc_holder
      t.decimal :aircraft_hours, precision: 8, scale: 1
      t.boolean :has_ica, null: false, default: false
      t.text :ica_notes
      t.text :notes
      t.timestamps
    end

    create_table :flight_logs do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.date :date, null: false
      t.decimal :tach_time, precision: 6, scale: 1, null: false
      t.decimal :tach_out, precision: 8, scale: 1
      t.decimal :tach_in, precision: 8, scale: 1
      t.decimal :hobbs_time, precision: 6, scale: 1
      t.decimal :hobbs_out, precision: 8, scale: 1
      t.decimal :hobbs_in, precision: 8, scale: 1
      t.string :departure_location
      t.string :destination_location
      t.text :route
      t.decimal :oil_added, precision: 6, scale: 2
      t.string :oil_added_type
      t.decimal :oil_level_after, precision: 6, scale: 2
      t.decimal :fuel_added, precision: 8, scale: 2
      t.string :fuel_added_type
      t.decimal :fuel_level_after, precision: 8, scale: 2
      t.text :notes
      t.timestamps
    end

    create_table :consumable_records do |t|
      t.references :aircraft, null: false, foreign_key: true
      t.references :flight_log, foreign_key: { on_delete: :nullify }
      t.string :record_type, null: false
      t.date :date, null: false
      t.decimal :quantity_added, precision: 6, scale: 2, null: false
      t.decimal :level_after, precision: 6, scale: 2
      t.string :consumable_type
      t.decimal :flight_hours, precision: 8, scale: 1, null: false
      t.text :notes
      t.boolean :excluded_from_averages, null: false, default: false
      t.timestamps
    end
    add_index :consumable_records, [ :aircraft_id, :record_type, :flight_hours ]
  end
end

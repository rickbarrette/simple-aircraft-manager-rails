# The REST API (docs/api.md): tokens, webhooks, idempotent writes, and links
# from SAM records to the other system's ids ("redmine:issue:4512").
class CreateApi < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "personal" # personal | integration
      t.references :user, null: false, foreign_key: true # the owner (personal) or the admin who made it (integration)
      t.string :token_digest, null: false
      t.string :token_hint, null: false # the first characters, to tell tokens apart
      t.json :scopes, null: false, default: []
      t.json :aircraft_ids # integration: the aircraft it may reach
      t.datetime :last_used_at
      t.string :last_used_ip
      t.datetime :revoked_at
      t.timestamps
      t.index :token_digest, unique: true
    end

    create_table :webhook_endpoints do |t|
      t.references :api_token, null: false, foreign_key: true
      t.string :url, null: false
      t.text :secret, null: false
      t.json :events, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    create_table :webhook_deliveries do |t|
      t.references :webhook_endpoint, null: false, foreign_key: true
      t.string :event, null: false
      t.text :payload, null: false
      t.string :status, null: false, default: "pending" # pending | delivered | failed
      t.integer :attempts, null: false, default: 0
      t.integer :response_status
      t.string :last_error
      t.datetime :delivered_at
      t.timestamps
      t.index [ :webhook_endpoint_id, :created_at ]
    end

    create_table :api_idempotency_keys do |t|
      t.references :api_token, null: false, foreign_key: true
      t.string :key, null: false
      t.string :request_digest, null: false
      t.integer :response_status, null: false
      t.text :response_body, null: false
      t.datetime :created_at, null: false
      t.index [ :api_token_id, :key ], unique: true
    end

    add_column :squawks, :external_ref, :string
    add_index :squawks, :external_ref
    add_column :record_versions, :api_token_id, :integer
  end
end

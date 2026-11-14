class AddPushAndOfflineSquawks < ActiveRecord::Migration[8.1]
  def change
    # Web Push subscriptions: one per browser or installed app a user turned notifications on in.
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :user_agent
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true

    # Squawks reported offline are sent later with a one-time key, like flights.
    add_column :squawks, :client_key, :string
    add_index :squawks, [ :aircraft_id, :client_key ], unique: true

    # Overdue items owners were already notified about (so each is sent once).
    add_column :aircraft, :notified_issue_keys, :json, null: false, default: []
  end
end

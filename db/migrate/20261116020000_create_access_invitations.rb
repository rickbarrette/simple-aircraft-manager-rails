# Invitation codes (AccessInvitation): a link someone opens to create an
# account, or accept with the one they have, and get roles on aircraft.
class CreateAccessInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :access_invitations do |t|
      t.string :label, null: false
      t.string :email
      t.string :name
      t.string :token_digest, null: false
      t.integer :max_uses
      t.integer :uses_count, null: false, default: 0
      t.datetime :expires_at
      t.datetime :revoked_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :access_invitations, :token_digest, unique: true

    create_table :access_invitation_roles do |t|
      t.references :access_invitation, null: false, foreign_key: true
      t.references :aircraft, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.timestamps
    end
    add_index :access_invitation_roles, %i[access_invitation_id aircraft_id], unique: true, name: "index_access_invitation_roles_unique"

    create_table :access_invitation_redemptions do |t|
      t.references :access_invitation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :access_invitation_redemptions, %i[access_invitation_id user_id], unique: true, name: "index_access_invitation_redemptions_unique"
  end
end

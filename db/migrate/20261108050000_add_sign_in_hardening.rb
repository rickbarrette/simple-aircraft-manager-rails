class AddSignInHardening < ActiveRecord::Migration[8.1]
  def change
    # Account lockout after repeated failed sign-ins (from any address).
    add_column :users, :failed_sign_ins, :integer, null: false, default: 0
    add_column :users, :locked_until, :datetime
    # Authenticator app (TOTP) as a second factor for password sign-in.
    add_column :users, :otp_secret, :text
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_used_at, :integer # last accepted time step (no replays)
    add_column :users, :otp_recovery_codes, :json
  end
end

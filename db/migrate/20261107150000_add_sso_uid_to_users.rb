class AddSsoUidToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sso_uid, :string
    add_index :users, :sso_uid, unique: true
  end
end

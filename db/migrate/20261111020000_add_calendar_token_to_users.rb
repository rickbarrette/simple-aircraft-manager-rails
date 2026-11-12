class AddCalendarTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    # Secret for the user's calendar feed URL (calendar apps can't sign in).
    add_column :users, :calendar_token, :string
    add_index :users, :calendar_token, unique: true
  end
end

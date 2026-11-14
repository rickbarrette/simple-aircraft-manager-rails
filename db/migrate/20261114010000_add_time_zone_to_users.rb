class AddTimeZoneToUsers < ActiveRecord::Migration[8.1]
  def change
    # The user's time zone for showing times; blank follows their device.
    add_column :users, :time_zone, :string
  end
end

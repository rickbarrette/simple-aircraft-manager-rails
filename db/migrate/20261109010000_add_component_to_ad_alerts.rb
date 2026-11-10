class AddComponentToAdAlerts < ActiveRecord::Migration[8.1]
  def change
    # The installed component whose make/model matched, so tracking the AD
    # makes it apply to that component (an appliance AD: magneto, ELT, radio…).
    add_reference :ad_alerts, :component, foreign_key: { on_delete: :nullify }
  end
end

# - squawks: deferring inoperative equipment under 14 CFR 91.213(d), and the
#   logbook entry that recorded the fix
# - components / documents: an expiration date (ELT battery per 91.207(c),
#   registration per 47.40, insurance…)
# - users: opt out of the weekly reminder email
class AddDeferralsExpirationsReminders < ActiveRecord::Migration[8.1]
  def change
    change_table :squawks do |t|
      t.datetime :deferred_at
      t.string :deferred_by_name
      t.string :deferred_by_role
      t.string :deferral_action
      t.text :deferral_notes
      t.references :logbook_entry, foreign_key: { on_delete: :nullify }
    end
    add_column :components, :expires_on, :date
    add_column :documents, :expires_on, :date
    add_column :users, :reminder_emails, :boolean, null: false, default: true
  end
end

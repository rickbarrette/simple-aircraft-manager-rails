# Component limits can be set in months or years (stored as months), not
# only days: "replace every 12 months" lands on the same date next year.
class AddMonthIntervalsToComponents < ActiveRecord::Migration[8.1]
  def change
    add_column :components, :replacement_months, :integer
    add_column :components, :tbo_months, :integer
    add_column :components, :inspection_months, :integer
  end
end

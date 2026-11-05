# The per-aircraft DRS search link turned out to be unnecessary: each AD's
# DRS link comes from the Excel import.
class RemoveDrsSearchUrlFromAircraft < ActiveRecord::Migration[8.1]
  def change
    remove_column :aircraft, :drs_search_url, :string if column_exists?(:aircraft, :drs_search_url)
  end
end

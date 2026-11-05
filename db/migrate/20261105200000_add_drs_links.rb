# Links to FAA DRS: per-AD document link and the owner's saved DRS search.
# Guarded because these columns were briefly part of an earlier migration.
class AddDrsLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :airworthiness_directives, :document_url, :string unless column_exists?(:airworthiness_directives, :document_url)
    add_column :aircraft, :drs_search_url, :string unless column_exists?(:aircraft, :drs_search_url)
  end
end

# What 14 CFR 43.9 / 43.11 and 91.417(a)(2)(v) want in the records:
# the signer's certificate (kind and number), an inspection's outcome, and
# each AD's method of compliance and the revision complied with.
class AddRecordKeepingFields < ActiveRecord::Migration[8.1]
  def up
    add_column :logbook_entries, :signoff_certificate_type, :string
    add_column :logbook_entries, :signoff_certificate_number, :string
    add_column :logbook_entries, :inspection_result, :string
    add_column :ad_compliances, :compliance_method, :string
    add_column :ad_compliances, :ad_revision, :string

    execute "UPDATE ad_compliances SET compliance_method = 'not_applicable' WHERE not_applicable = 1"
    execute "UPDATE ad_compliances SET compliance_method = 'terminating' WHERE compliance_method IS NULL AND permanent = 1"
    execute "UPDATE ad_compliances SET compliance_method = 'inspection' WHERE compliance_method IS NULL"
  end

  def down
    remove_column :logbook_entries, :signoff_certificate_type
    remove_column :logbook_entries, :signoff_certificate_number
    remove_column :logbook_entries, :inspection_result
    remove_column :ad_compliances, :compliance_method
    remove_column :ad_compliances, :ad_revision
  end
end

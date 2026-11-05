class AddFaaFieldsToAds < ActiveRecord::Migration[8.1]
  def change
    add_column :airworthiness_directives, :effective_date, :date
    add_column :airworthiness_directives, :supersedes, :string
    add_column :airworthiness_directives, :superseded_by, :string
    add_column :airworthiness_directives, :docket_number, :string
    add_column :airworthiness_directives, :applicable_models, :text
    add_column :airworthiness_directives, :product_type, :string

    # Per-aircraft "this AD does not apply" determination (e.g. equipment not installed).
    add_column :ad_compliances, :not_applicable, :boolean, null: false, default: false
  end
end

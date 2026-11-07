# Oil analysis results go from one column per AvLab element to per-element
# hashes, so labs that test more elements (Blackstone reports 20) fit. Adds oil
# type, oil properties (viscosity, flash point…) and "exclude from averages",
# and switches to the original app's statuses (normal / monitor / action required).
class MoveOilAnalysisResultsToJson < ActiveRecord::Migration[8.1]
  ELEMENTS = %w[iron copper nickel chromium silver magnesium aluminum lead silicon titanium tin molybdenum].freeze
  STATUS_UP = { "elevated" => "monitor", "high" => "action_required" }.freeze

  class Row < ActiveRecord::Base
    self.table_name = "oil_analyses"
  end

  def up
    add_column :oil_analyses, :elements, :json, null: false, default: {}
    add_column :oil_analyses, :element_averages, :json, null: false, default: {}
    add_column :oil_analyses, :oil_properties, :json, null: false, default: {}
    add_column :oil_analyses, :oil_type, :string
    add_column :oil_analyses, :excluded_from_averages, :boolean, null: false, default: false
    change_column_null :oil_analyses, :status, true
    change_column_default :oil_analyses, :status, from: "normal", to: nil

    Row.reset_column_information
    Row.find_each do |row|
      row.update_columns(
        elements: ELEMENTS.to_h { [ _1, row[_1]&.to_f ] }.compact,
        element_averages: ELEMENTS.to_h { [ _1, row["#{_1}_avg"]&.to_f ] }.compact,
        status: STATUS_UP.fetch(row.status, row.status)
      )
    end

    ELEMENTS.each do |el|
      remove_column :oil_analyses, el
      remove_column :oil_analyses, :"#{el}_avg"
    end
  end

  def down
    ELEMENTS.each do |el|
      add_column :oil_analyses, el, :decimal, precision: 8, scale: 1
      add_column :oil_analyses, :"#{el}_avg", :decimal, precision: 8, scale: 1
    end

    Row.reset_column_information
    Row.find_each do |row|
      values = ELEMENTS.to_h { [ _1, row.elements[_1] ] }
      averages = ELEMENTS.to_h { [ "#{_1}_avg", row.element_averages[_1] ] }
      row.update_columns(values.merge(averages).merge(status: STATUS_UP.invert.fetch(row.status, row.status || "normal")))
    end

    change_column_default :oil_analyses, :status, from: nil, to: "normal"
    change_column_null :oil_analyses, :status, false
    remove_column :oil_analyses, :elements
    remove_column :oil_analyses, :element_averages
    remove_column :oil_analyses, :oil_properties
    remove_column :oil_analyses, :oil_type
    remove_column :oil_analyses, :excluded_from_averages
  end
end

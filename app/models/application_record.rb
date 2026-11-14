class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  before_validation :default_blank_required_columns
  validate :optional_references_exist

  private

  # A blank form field arrives as nil; for a column that can't be empty and has
  # a default (a checkbox, a count, a position), use the default rather than
  # failing in the database.
  def default_blank_required_columns
    self.class.columns.each do |column|
      next if column.null || column.default.nil? || !self[column.name].nil?
      self[column.name] = self.class.type_for_attribute(column.name).cast(column.default)
    end
  end

  # An optional link (a parent part, a collection…) given an id that doesn't
  # exist is a mistake in the form, not something to store.
  def optional_references_exist
    self.class.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.polymorphic? || !assoc.options[:optional]
      next if self[assoc.foreign_key].blank? || !attribute_changed?(assoc.foreign_key)
      errors.add(assoc.name, :invalid) unless public_send(assoc.name)
    end
  end
end

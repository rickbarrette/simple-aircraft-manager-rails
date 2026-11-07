# A sub-component a logbook entry also covers (the oil filter on the engine…)
# and its times at the entry.
class LogbookEntryPart < ApplicationRecord
  include Versioned
  belongs_to :logbook_entry
  belongs_to :component

  validates :component_id, uniqueness: { scope: :logbook_entry_id }
  validates :hours_at_entry, :since_overhaul_at_entry, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Part of a signed entry's content: locked with it.
  before_save { throw :abort if logbook_entry&.signed? }
  before_destroy { throw :abort if logbook_entry&.signed? && !destroyed_by_association }
end

# An adopted revision of the procedures document, kept for good (the
# superseded ones are the archive, as AC 120-78B 4.3.8 asks of manuals).
class ProceduresRevision < ApplicationRecord
  belongs_to :adopted_by, class_name: "User", optional: true

  scope :latest_first, -> { order(number: :desc) }
  before_update { throw :abort }
  before_destroy { throw :abort }

  def self.current = latest_first.first
end

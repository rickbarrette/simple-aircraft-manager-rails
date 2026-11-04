class AircraftNote < ApplicationRecord
  belongs_to :aircraft
  belongs_to :user, optional: true

  validates :text, presence: true
  scope :visible_publicly, -> { where(public: true) }
  scope :recent_first, -> { order(created_at: :desc) }
end

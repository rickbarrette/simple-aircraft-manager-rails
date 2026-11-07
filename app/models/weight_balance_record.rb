# One weight & balance report: the aircraft's empty weight and CG as of a
# date, usually after weighing or an equipment change (each alteration that
# changes them needs a new one; its 337 can be linked).
class WeightBalanceRecord < ApplicationRecord
  include Versioned
  belongs_to :aircraft
  belongs_to :major_record, optional: true
  belongs_to :document, optional: true

  validates :date, presence: true
  validates :empty_weight, numericality: { greater_than: 0 }
  validates :empty_arm, numericality: true
  validates :max_gross_weight, numericality: { greater_than: 0 }, allow_nil: true
  validate { errors.add(:max_gross_weight, "must be more than the empty weight") if max_gross_weight && empty_weight && max_gross_weight <= empty_weight }

  scope :recent_first, -> { order(date: :desc, created_at: :desc) }

  def empty_moment = empty_weight * empty_arm
  def useful_load = max_gross_weight && max_gross_weight - empty_weight
end

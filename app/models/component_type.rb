class ComponentType < ApplicationRecord
  has_many :components, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  scope :ordered, -> { order(:name) }
  def to_s = name
end

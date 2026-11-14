class DocumentCollection < ApplicationRecord
  VISIBILITIES = LabelSet.new("document_collection.visibilities", %w[private status maintenance])

  belongs_to :aircraft
  has_many :documents, dependent: :destroy

  validates :name, presence: true
  validates :visibility, inclusion: { in: VISIBILITIES.keys }

  scope :ordered, -> { order(starred: :desc, name: :asc) }
  def to_s = name
end

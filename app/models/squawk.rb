class Squawk < ApplicationRecord
  include UploadValidation

  PRIORITIES = { 0 => "Ground Aircraft", 1 => "Fix Soon", 2 => "Fix at Next Inspection", 3 => "Fix Eventually" }.freeze
  PRIORITY_COLORS = { 0 => "red", 1 => "orange", 2 => "blue", 3 => "gray" }.freeze

  belongs_to :aircraft
  belongs_to :component, optional: true
  belongs_to :reported_by, class_name: "User", optional: true
  has_one_attached :attachment

  validates :priority, inclusion: { in: PRIORITIES.keys }
  validates :issue_reported, presence: true
  validates_uploads :attachment

  scope :active, -> { where(resolved: false) }
  scope :resolved, -> { where(resolved: true) }
  scope :by_priority, -> { order(:priority, created_at: :desc) }

  def priority_label = PRIORITIES[priority]
  def priority_color = PRIORITY_COLORS[priority]
  def grounding? = priority.zero? && !resolved?

  def resolve!(notes: nil)
    update!(resolved: true, resolved_at: Time.current, notes: [ self.notes, notes ].compact_blank.join("\n\n"))
  end
end

# A user's FAA certificate (A&P, IA, pilot…), used to sign logbook entries.
# Some expire (an Inspection Authorization lapses on March 31 of each
# odd-numbered year unless renewed, 14 CFR 65.92).
class UserCertificate < ApplicationRecord
  KINDS = LogbookEntry::CERTIFICATE_TYPES
  MECHANIC_KINDS = %w[AP IA A P REPAIR_STATION REPAIRMAN].freeze
  SHORT_LABELS = LabelSet.new("user_certificate.short_labels", %w[AP IA A P REPAIR_STATION REPAIRMAN PILOT OTHER])
  EXPIRY_WARNING_DAYS = 60

  belongs_to :user

  normalizes :number, with: ->(n) { n.strip }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :number, presence: true, length: { maximum: 40 }

  scope :ordered, -> { order(Arel.sql("CASE kind WHEN 'IA' THEN 0 WHEN 'AP' THEN 1 ELSE 2 END"), :created_at) }
  # Expiring soon, or lapsed in the last month (so it isn't mentioned forever).
  scope :expiring, ->(within = EXPIRY_WARNING_DAYS.days) { where(expires_on: (Date.current - 30)..(Date.current + within)) }

  def kind_label = KINDS[kind]
  def short_label = SHORT_LABELS[kind]
  def mechanic? = MECHANIC_KINDS.include?(kind)
  def expired?(today = Date.current) = expires_on.present? && today > expires_on
  def to_s = "#{kind_label} #{number}"
end

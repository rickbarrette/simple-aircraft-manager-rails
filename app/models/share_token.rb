class ShareToken < ApplicationRecord
  PRIVILEGES = { "status" => "Current Status", "maintenance" => "Maintenance Detail" }.freeze
  MAX_PER_AIRCRAFT = 10

  belongs_to :aircraft
  belongs_to :created_by, class_name: "User", optional: true
  has_secure_token :token, length: 32

  validates :privilege, inclusion: { in: PRIVILEGES.keys }
  validate :within_limit, on: :create

  scope :active, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

  def self.find_active(token)
    active.find_by(token: token.to_s)
  end

  def maintenance? = privilege == "maintenance"
  def expired? = expires_at.present? && expires_at < Time.current

  private

  def within_limit
    if aircraft && aircraft.share_tokens.count >= MAX_PER_AIRCRAFT
      errors.add(:base, "An aircraft can have at most #{MAX_PER_AIRCRAFT} share links")
    end
  end
end

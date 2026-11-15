# Where an integration wants to hear about changes (squawks, signed entries):
# SAM posts JSON there, signed with the shared secret (see WebhookDeliveryJob).
class WebhookEndpoint < ApplicationRecord
  EVENTS = LabelSet.new("webhook_endpoint.events", %w[squawk.created squawk.updated squawk.resolved entry.signed])

  belongs_to :api_token
  has_many :deliveries, class_name: "WebhookDelivery", dependent: :delete_all

  encrypts :secret

  normalizes :url, with: ->(u) { u.to_s.strip }
  validates :url, presence: true, format: { with: %r{\Ahttps?://[^\s/]+(:\d+)?(/\S*)?\z}i }
  validates :secret, presence: true, length: { minimum: 16 }
  validate :events_known

  scope :enabled, -> { where(enabled: true) }

  def self.new_secret = SecureRandom.hex(32)

  def subscribed?(event) = events.include?(event.to_s)

  private

  def events_known
    errors.add(:events, :blank) if events.blank?
    errors.add(:events, :inclusion) if (Array(events) - EVENTS.keys).any?
  end
end

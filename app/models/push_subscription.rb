# A browser or installed app where a user turned notifications on (Profile).
class PushSubscription < ApplicationRecord
  # The browsers' push services. The server posts to the endpoint, so only
  # these hosts are accepted (not, say, an address inside the network).
  PUSH_SERVICES = /\A(([\w-]+\.)*googleapis\.com|([\w-]+\.)*google\.com|updates\.push\.services\.mozilla\.com|([\w-]+\.)*push\.apple\.com|([\w-]+\.)*notify\.windows\.com)\z/

  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh, :auth, presence: true
  validate :endpoint_is_a_push_service

  private

  def endpoint_is_a_push_service
    uri = URI.parse(endpoint.to_s)
    errors.add(:endpoint, :invalid) unless uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(PUSH_SERVICES)
  rescue URI::InvalidURIError
    errors.add(:endpoint, :invalid)
  end
end

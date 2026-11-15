# One event sent (or being sent) to a webhook endpoint; the recent ones are
# listed for the admin, with the answer the other system gave.
class WebhookDelivery < ApplicationRecord
  KEEP_FOR = 30.days

  belongs_to :webhook_endpoint

  scope :recent, -> { order(created_at: :desc) }

  def self.purge_old = where(created_at: ...KEEP_FOR.ago).delete_all
end

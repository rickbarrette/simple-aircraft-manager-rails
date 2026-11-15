# Tells integrations about changes (docs/api.md, "Webhooks"): each enabled
# endpoint subscribed to the event, whose token is active and reaches the
# aircraft, gets a delivery, sent by WebhookDeliveryJob after the change is
# saved.
module Webhooks
  module_function

  def publish(event, aircraft:, data:)
    endpoints = WebhookEndpoint.enabled.joins(:api_token).merge(ApiToken.active).includes(:api_token)
                               .select { _1.subscribed?(event) && Array(_1.api_token.aircraft_ids).include?(aircraft.id) }
    return if endpoints.empty?
    body = { event: event, id: SecureRandom.uuid, created_at: Time.current.utc.iso8601, aircraft_id: aircraft.id, data: data }.to_json
    endpoints.each do |endpoint|
      delivery = endpoint.deliveries.create!(event: event, payload: body)
      WebhookDeliveryJob.perform_later(delivery.id)
    end
  end
end

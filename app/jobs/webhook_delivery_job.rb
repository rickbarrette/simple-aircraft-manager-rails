require "net/http"

# Posts one webhook delivery. The body is signed so the receiver can check
# it came from here and wasn't replayed:
#   SAM-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<body>" with the endpoint's secret>
# Anything but a 2xx answer is retried with growing waits, then marked failed.
class WebhookDeliveryJob < ApplicationJob
  queue_as :default
  ATTEMPTS = 8

  class Failed < StandardError; end

  retry_on Failed, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    WebhookDelivery.find_by(id: job.arguments.first)&.update!(status: "failed", last_error: error.message.truncate(250))
  end

  def perform(delivery_id)
    delivery = WebhookDelivery.includes(:webhook_endpoint).find_by(id: delivery_id) or return
    return if delivery.status == "delivered"
    endpoint = delivery.webhook_endpoint
    delivery.increment!(:attempts)
    response = post(endpoint, delivery)
    if response.code.to_i.between?(200, 299)
      delivery.update!(status: "delivered", response_status: response.code.to_i, delivered_at: Time.current, last_error: nil)
    else
      delivery.update!(response_status: response.code.to_i, last_error: "HTTP #{response.code}")
      raise Failed, "HTTP #{response.code}"
    end
  rescue OutboundAddress::Blocked => e
    # Pointed at an address the server won't send to: retrying won't help.
    delivery.update!(status: "failed", last_error: "blocked address (#{e.reason})")
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError => e
    delivery.update!(last_error: "#{e.class.name.demodulize}: #{e.message}".truncate(250))
    raise Failed, e.message
  end

  private

  def post(endpoint, delivery)
    uri = URI.parse(endpoint.url)
    timestamp = Time.current.to_i
    signature = OpenSSL::HMAC.hexdigest("SHA256", endpoint.secret, "#{timestamp}.#{delivery.payload}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["User-Agent"] = "SimpleAircraftManager-Webhooks"
    req["SAM-Event"] = delivery.event
    req["SAM-Delivery"] = delivery.id.to_s
    req["SAM-Signature"] = "t=#{timestamp},v1=#{signature}"
    req.body = delivery.payload
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = OutboundAddress.resolve!(uri.host, allow_private: true) # set up by an admin: the private network is fine
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    http.start { _1.request(req) }
  end
end

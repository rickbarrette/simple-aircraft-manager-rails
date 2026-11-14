# Delivers one notification (see PushNotifier) to each of the users' devices.
# A device that's gone (the browser dropped the subscription) is forgotten.
class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_ids, key, path, tag, vars)
    vars = vars.symbolize_keys
    message = JSON.generate(title: I18n.t("push.#{key}.title", **vars), body: I18n.t("push.#{key}.body", **vars), path: path, tag: tag)
    PushSubscription.where(user_id: user_ids).find_each { deliver(_1, message) }
  end

  private

  def deliver(subscription, message)
    WebPush.payload_send(message: message, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
                         ttl: 1.day.to_i, urgency: "high",
                         vapid: { subject: PushKeys.subject, public_key: PushKeys.public_key, private_key: PushKeys.private_key })
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized
    subscription.destroy
  rescue WebPush::Error, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    Rails.logger.warn("[push] #{subscription.endpoint.truncate(60)}: #{e.class}: #{e.message.truncate(200)}")
  end
end

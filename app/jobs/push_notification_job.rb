# Delivers one notification (see PushNotifier) to each of the users' devices.
# A device that's gone (the browser dropped the subscription) is forgotten.
class PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_ids, key, path, tag, vars)
    message = self.class.message(key, path, tag, vars)
    PushSubscription.where(user_id: user_ids).find_each { self.class.deliver(_1, message) }
  end

  def self.message(key, path, tag, vars = {})
    vars = vars.symbolize_keys
    JSON.generate(title: I18n.t("push.#{key}.title", **vars), body: I18n.t("push.#{key}.body", **vars), path: path, tag: tag)
  end

  # Sends to one device: nil when the push service took it, else why not.
  def self.deliver(subscription, message)
    WebPush.payload_send(message: message, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
                         ttl: 1.day.to_i, urgency: "high",
                         vapid: { subject: PushKeys.subject, public_key: PushKeys.public_key, private_key: PushKeys.private_key })
    nil
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized => e
    subscription.destroy
    failure(subscription, e)
  rescue WebPush::Error, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    failure(subscription, e)
  end

  def self.failure(subscription, error)
    reason = "#{error.class.name.demodulize}: #{error.message.truncate(200)}"
    Rails.logger.warn("[push] #{subscription.endpoint.truncate(60)}: #{reason}")
    reason
  end
  private_class_method :failure
end

# Sends a notification to every device where the users turned notifications
# on. The text is push.<key>.title / .body in config/locales, filled in when
# it's sent.
#   PushNotifier.notify(users, :grounding_squawk, path: "/aircraft/1/squawks", tail: "N12345", issue: "…")
module PushNotifier
  module_function

  def notify(users, key, path:, tag: nil, **vars)
    ids = Array(users).map { _1.respond_to?(:id) ? _1.id : _1 }.compact.uniq
    return if ids.empty? || !PushSubscription.exists?(user_id: ids)
    PushNotificationJob.perform_later(ids, key.to_s, path, tag, vars.transform_values { _1.is_a?(Numeric) ? _1 : _1.to_s })
  end
end

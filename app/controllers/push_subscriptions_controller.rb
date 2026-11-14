# Notifications on this device (Profile): the browser's push subscription is
# saved here when the user turns them on, and removed when they turn them off.
class PushSubscriptionsController < ApplicationController
  def create
    sub = params.require(:subscription).permit(:endpoint, keys: %i[p256dh auth])
    record = PushSubscription.find_or_initialize_by(endpoint: sub[:endpoint].to_s)
    record.assign_attributes(user: current_user, p256dh: sub.dig(:keys, :p256dh), auth: sub.dig(:keys, :auth),
                             user_agent: request.user_agent.to_s.first(250))
    if record.save
      head :created
    else
      render json: { error: t("flash.push_subscriptions.not_saved", host: URI.parse(record.endpoint).host.to_s) }, status: :unprocessable_entity
    end
  rescue URI::InvalidURIError
    render json: { error: t("flash.push_subscriptions.not_saved", host: "?") }, status: :unprocessable_entity
  end

  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint].to_s).destroy_all
    head :no_content
  end

  # A notification to each of this user's devices, sent now so the page can
  # say which push services took it (and why one didn't).
  def test
    message = PushNotificationJob.message("test", edit_profile_path, "test")
    devices = current_user.push_subscriptions.order(:created_at).map do |sub|
      { device: device_name(sub.user_agent), error: PushNotificationJob.deliver(sub, message) }
    end
    render json: { devices: devices }
  end

  private

  # "Chrome on Android" from the browser's description of itself.
  def device_name(agent)
    browser = case agent
    when /Edg\//, /EdgA\// then "Edge"
    when /SamsungBrowser/ then "Samsung Internet"
    when /Firefox|FxiOS/ then "Firefox"
    when /Chrome|CriOS/ then "Chrome"
    when /Safari/ then "Safari"
    end
    system = case agent
    when /Android/ then "Android"
    when /iPhone/ then "iPhone"
    when /iPad/ then "iPad"
    when /Macintosh/ then "Mac"
    when /Windows/ then "Windows"
    when /Linux/ then "Linux"
    end
    [ browser, system ].compact.join(" · ").presence || t("flash.push_subscriptions.unknown_device")
  end
end

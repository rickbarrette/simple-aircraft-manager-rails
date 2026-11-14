# Notifications on this device (Profile): the browser's push subscription is
# saved here when the user turns them on, and removed when they turn them off.
class PushSubscriptionsController < ApplicationController
  def create
    sub = params.require(:subscription).permit(:endpoint, keys: %i[p256dh auth])
    record = PushSubscription.find_or_initialize_by(endpoint: sub[:endpoint].to_s)
    record.assign_attributes(user: current_user, p256dh: sub.dig(:keys, :p256dh), auth: sub.dig(:keys, :auth),
                             user_agent: request.user_agent.to_s.first(250))
    record.save ? head(:created) : head(:unprocessable_entity)
  end

  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint].to_s).destroy_all
    head :no_content
  end

  # A notification to this user's devices, to check they arrive.
  def test
    PushNotifier.notify(current_user, :test, path: edit_profile_path, tag: "test")
    head :accepted
  end
end

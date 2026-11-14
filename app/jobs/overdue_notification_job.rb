# Daily: tells owners about items that have newly become overdue or limit
# the aircraft (grounded, VFR only…). Each is sent once; one that's fixed and
# becomes overdue again is sent again.
class OverdueNotificationJob < ApplicationJob
  queue_as :default

  def perform
    Aircraft.includes(roles: :user).find_each do |aircraft|
      issues = aircraft.airworthiness.issues.select { _1.severity.in?([ Airworthiness::RED, Airworthiness::LIMITED ]) }
      keys = issues.map { |i| "#{i.category}:#{i.item.class.name}:#{i.item.id}" }
      fresh = issues.reject.with_index { |_, n| aircraft.notified_issue_keys.include?(keys[n]) }
      owners = aircraft.roles.select { _1.role == "owner" }.map(&:user).reject(&:disabled?)
      if fresh.any?
        PushNotifier.notify(owners, :overdue, path: Rails.application.routes.url_helpers.aircraft_path(aircraft), tag: "overdue-#{aircraft.id}",
                                              tail: aircraft.tail_number, items: fresh.map(&:title).to_sentence, count: fresh.size)
      end
      aircraft.update_column(:notified_issue_keys, keys) if keys.sort != aircraft.notified_issue_keys.sort
    end
  end
end

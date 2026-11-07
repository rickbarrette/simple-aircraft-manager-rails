# Weekly: look for newly published ADs for every aircraft.
class AdWatchJob < ApplicationJob
  queue_as :default

  def perform
    Aircraft.find_each do |aircraft|
      AdWatch.new(aircraft).check!
    rescue AdWatch::Error => e
      Rails.logger.warn("[ad watch] #{aircraft.tail_number}: #{e.message}")
    end
  end
end

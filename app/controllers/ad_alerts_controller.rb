# Newly published ADs that may apply: check now, track or dismiss, and the
# search terms used.
class AdAlertsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_alert, only: %i[track dismiss]
  rate_limit to: 5, within: 1.minute, only: :check, with: -> { redirect_to aircraft_airworthiness_directives_path(@aircraft), alert: "Try again in a minute." }

  def check
    found = AdWatch.new(@aircraft).check!
    redirect_to aircraft_airworthiness_directives_path(@aircraft, anchor: "new-ads"),
                notice: found.any? ? "Found #{helpers.pluralize(found.size, 'newly published AD')} to review." : "No new ADs found for #{AdWatch.new(@aircraft).terms.to_sentence}."
  rescue AdWatch::Error => e
    redirect_to aircraft_airworthiness_directives_path(@aircraft), alert: "Couldn't check for new ADs: #{e.message}."
  end

  def track
    ad = @alert.track!
    log_event("ad", "AD tracked from the Federal Register: #{ad.name}")
    redirect_to edit_aircraft_airworthiness_directive_path(@aircraft, ad),
                notice: "#{ad.name} is now tracked. Set its applicability and recurrence from the AD's text, then record compliance or mark it not applicable."
  end

  def dismiss
    @alert.dismiss!
    redirect_to aircraft_airworthiness_directives_path(@aircraft, anchor: "new-ads"), notice: "Dismissed."
  end

  def terms
    @aircraft.update!(ad_watch_terms: params[:ad_watch_terms].to_s.strip.first(500).presence)
    redirect_to aircraft_airworthiness_directives_path(@aircraft, anchor: "new-ads"), notice: "Search terms saved."
  end

  private

  def set_alert = @alert = @aircraft.ad_alerts.find(params[:id])
end

# Newly published ADs that may apply: check now, track or dismiss, and the
# search terms used.
class AdAlertsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_alert, only: %i[track dismiss]
  rate_limit to: 5, within: 1.minute, only: :check, with: -> { redirect_to aircraft_airworthiness_directives_path(@aircraft), alert: t("flash.ad_alerts.try_again_in_a") }

  def check
    found = AdWatch.new(@aircraft).check!
    redirect_to aircraft_airworthiness_directives_path(@aircraft, anchor: "new-ads"),
                notice: found.any? ? t("flash.ad_alerts.found", count: found.size) : t("flash.ad_alerts.none_found", terms: AdWatch.new(@aircraft).terms.map(&:label).uniq.to_sentence)
  rescue AdWatch::Error => e
    redirect_to aircraft_airworthiness_directives_path(@aircraft), alert: t("flash.ad_alerts.couldn_t_check_for", message: e.message)
  end

  def track
    ad = @alert.track!
    log_event("ad", t("flash.ad_alerts.ad_tracked_from_the", name: ad.name))
    redirect_to edit_aircraft_airworthiness_directive_path(@aircraft, ad),
                notice: t("flash.ad_alerts.is_now_tracked_set", name: ad.name)
  end

  def dismiss
    @alert.dismiss!
    redirect_to aircraft_airworthiness_directives_path(@aircraft, anchor: "new-ads"), notice: t("flash.ad_alerts.dismissed")
  end

  def terms
    @aircraft.update!(ad_watch_terms: params[:ad_watch_terms].to_s.strip.first(500).presence)
    redirect_to aircraft_airworthiness_directives_path(@aircraft, anchor: "new-ads"), notice: t("flash.ad_alerts.search_terms_saved")
  end

  private

  def set_alert = @alert = @aircraft.ad_alerts.find(params[:id])
end

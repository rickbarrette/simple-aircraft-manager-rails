# The signed-in user's AirTrail sync settings (Profile → AirTrail).
class AirTrailConnectionsController < ApplicationController
  before_action :set_connection, except: %i[show create]

  def show
    @connection = current_user.air_trail_connection || current_user.build_air_trail_connection
    return unless @connection.persisted?
    @counts = @connection.counts
    @failed = @connection.syncs.failed.includes(flight_log: :aircraft).order(updated_at: :desc).limit(20)
    @unresolved = @connection.unresolved_airport_codes
    @flight_count = FlightLog.where(user: current_user).count
  end

  def create
    @connection = current_user.build_air_trail_connection(connection_params)
    save_and_verify
  end

  def update
    attrs = connection_params
    attrs.delete(:api_key) if attrs[:api_key].blank? # keep the stored key
    url_changed = attrs[:base_url].present? && attrs[:base_url].chomp("/") != @connection.base_url
    @connection.assign_attributes(attrs)
    @connection.remote_user_id = nil if url_changed || attrs.key?(:api_key) # re-identify
    save_and_verify
  end

  def test
    verify
    redirect_to air_trail_connection_path
  end

  # Link existing AirTrail flights and push everything else, in the background.
  def sync
    AirTrailBackfillJob.perform_later(@connection.id)
    redirect_to air_trail_connection_path, notice: t("flash.air_trail_connections.sync_started_refresh_this")
  end

  def map_airport
    code = params[:code].to_s.strip.upcase
    target = params[:airtrail_code].to_s.strip.upcase
    match = target.present? && AirTrailSyncer.new(@connection).map_airport(code, target)
    if match
      AirTrailBackfillJob.perform_later(@connection.id) # retry flights that needed it
      redirect_to air_trail_connection_path, notice: t("flash.air_trail_connections.mapped_to_retrying_affected", code: code, icao: match["icao"], name: match["name"])
    else
      redirect_to air_trail_connection_path, alert: t("flash.air_trail_connections.airtrail_has_no_airport", target: target)
    end
  rescue AirTrailClient::Error => e
    redirect_to air_trail_connection_path, alert: e.message
  end

  # Stops syncing. Flights already in AirTrail are left there.
  def destroy
    @connection.destroy!
    redirect_to air_trail_connection_path, notice: t("flash.air_trail_connections.airtrail_disconnected_flights_already")
  end

  private

  def set_connection
    @connection = current_user.air_trail_connection or redirect_to(air_trail_connection_path)
  end

  def connection_params
    params.require(:air_trail_connection).permit(:base_url, :api_key, :enabled)
  end

  def save_and_verify
    if @connection.save
      verify
      redirect_to air_trail_connection_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  def verify
    me = @connection.client.me
    scopes = Array(me.dig("credential", "scopes"))
    missing = me.dig("credential", "kind") == "apiKey" ? AirTrailConnection::REQUIRED_SCOPES - scopes : []
    @connection.update!(remote_user_id: me["id"], remote_username: me["username"], checked_at: Time.current,
                        status: missing.empty? ? "ok" : "error",
                        last_error: missing.empty? ? nil : t("flash.air_trail_connections.missing_scopes", scopes: missing.join(", ")))
    if missing.empty?
      flash[:notice] = t("flash.air_trail_connections.connected_to_airtrail_as", username: me["username"])
    else
      flash[:alert] = @connection.last_error
    end
  rescue AirTrailClient::Error => e
    @connection.update!(status: "error", last_error: e.message, checked_at: Time.current)
    flash[:alert] = e.message
  end
end

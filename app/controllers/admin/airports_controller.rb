# Admin → Airports: OurAirports updates and custom airports.
class Admin::AirportsController < ApplicationController
  before_action :require_admin!
  before_action :set_airport, only: %i[edit update destroy]

  def index
    @total = Airport.count
    @custom = Airport.custom.order(:ident)
    @updates = AirportUpdate.recent_first.includes(:requested_by).limit(5)
    @running = AirportUpdate.in_progress.exists?
    @last_success = AirportUpdate.last_success
    @query = params[:q].to_s.strip
    @results = @query.present? ? Airport.search(@query, limit: 20) : []
  end

  # Queue a download + sync from OurAirports.
  def refresh
    if AirportUpdate.in_progress.exists?
      redirect_to admin_airports_path, alert: t("flash.admin_airports.an_update_is_already")
    else
      update = AirportUpdate.create!(source_url: AirportData::SOURCE_URL, requested_by: current_user)
      AirportUpdateJob.perform_later(update.id)
      redirect_to admin_airports_path, notice: t("flash.admin_airports.airport_update_started_refresh")
    end
  end

  def new
    @airport = Airport.new(custom: true, kind: "small_airport", ident: params[:ident])
  end

  def create
    @airport = Airport.new(airport_params.merge(custom: true))
    if @airport.save
      redirect_to admin_airports_path, notice: t("flash.admin_airports.custom_airport_added", ident: @airport.ident)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @airport.update(airport_params)
      redirect_to admin_airports_path, notice: t("flash.admin_airports.updated", ident: @airport.ident)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @airport.destroy!
    redirect_to admin_airports_path, notice: t("flash.admin_airports.removed", ident: @airport.ident)
  end

  private

  # Only custom airports can be edited; OurAirports data comes from updates.
  def set_airport = @airport = Airport.custom.find(params[:id])

  def airport_params
    params.require(:airport).permit(:ident, :name, :kind, :municipality, :region, :country, :latitude, :longitude, :elevation_ft, :gps_code, :local_code, :iata)
  end
end

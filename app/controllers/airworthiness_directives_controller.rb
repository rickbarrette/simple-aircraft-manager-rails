class AirworthinessDirectivesController < ApplicationController
  include AircraftScoped
  include Applicability
  before_action :require_owner!, except: :index
  before_action :set_ad, only: %i[edit update destroy]

  def index
    @rows = Compliance.ad_rows(@aircraft)
    @history = AdCompliance.for_aircraft(@aircraft).recent_first
                           .includes(:component, :logbook_entry, airworthiness_directive: :document, inspection_record: :inspection_type)
    @attachable = AirworthinessDirective.where.not(id: @aircraft.applicable_ads.select(:id)).ordered if owner?
  end

  def new
    @ad = AirworthinessDirective.new
    @applies_to_airframe = true
  end

  def create
    @ad = AirworthinessDirective.new(ad_params)
    AirworthinessDirective.transaction do
      @ad.save!
      apply_applicability(@ad, to_airframe: applies_to_airframe?, component_ids: applicable_component_ids)
    end
    log_event("ad", "#{@ad.bulletin_label} added: #{@ad.name}")
    redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "#{@ad.bulletin_label} added."
  rescue ActiveRecord::RecordInvalid
    @applies_to_airframe = applies_to_airframe?
    render :new, status: :unprocessable_entity
  end

  # Link an AD that already exists (e.g. tracked on another aircraft).
  def attach
    ad = AirworthinessDirective.find(params[:airworthiness_directive_id])
    ad.aircraft << @aircraft unless ad.aircraft.include?(@aircraft)
    log_event("ad", "#{ad.bulletin_label} linked: #{ad.name}")
    redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "#{ad.name} linked."
  end

  def edit
    @applies_to_airframe = @ad.aircraft.include?(@aircraft)
  end

  def update
    AirworthinessDirective.transaction do
      @ad.update!(ad_params)
      apply_applicability(@ad, to_airframe: applies_to_airframe?, component_ids: applicable_component_ids)
    end
    log_event("ad", "#{@ad.bulletin_label} updated: #{@ad.name}")
    redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "#{@ad.bulletin_label} updated."
  rescue ActiveRecord::RecordInvalid
    @applies_to_airframe = applies_to_airframe?
    render :edit, status: :unprocessable_entity
  end

  # Removes the AD from this aircraft (the shared AD record survives if other aircraft use it).
  def destroy
    detach_from_aircraft(@ad)
    log_event("ad", "#{@ad.bulletin_label} removed: #{@ad.name}")
    redirect_to aircraft_airworthiness_directives_path(@aircraft), notice: "#{@ad.name} removed from #{@aircraft.tail_number}."
  end

  private

  def set_ad = @ad = @aircraft.applicable_ads.find(params[:id])

  def ad_params
    p = params.require(:airworthiness_directive).permit(
      :name, :short_description, :required_action, :compliance_type, :trigger_condition, :recurring,
      :recurring_hours, :recurring_months, :recurring_days, :bulletin_type, :mandatory, :document_id, :document_url
    )
    p[:document_id] = scoped_id(@aircraft.documents, p[:document_id])
    p
  end
end

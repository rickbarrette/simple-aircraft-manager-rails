# Logbook entries as a PDF to print on labels or pages and put in the paper
# logbook (where they're signed by hand).
class LogbookPrintsController < ApplicationController
  include AircraftScoped
  before_action :set_entries

  def new
    @layout = params[:layout].presence || "avery_5164"
  end

  def show
    pdf = LogbookEntryPdf.new(@aircraft, @entries, layout: params[:layout], start_at: params[:start_at])
    log_event("logbook", t("flash.logbook_prints.logbook_entries_printed", count: @entries.size))
    send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
  end

  private

  def set_entries
    ids = Array(params[:ids]).map(&:to_i).first(200)
    @entries = @aircraft.logbook_entries.where(id: ids).includes(:component, :parts, :signature, inspection_records: :inspection_type).order(:date, :id).to_a
    redirect_to aircraft_logbook_entries_path(@aircraft), alert: t("flash.logbook_prints.choose_the_entries_to") if @entries.empty?
  end
end

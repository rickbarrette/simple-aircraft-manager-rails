# Signing a logbook entry electronically (AC 120-78B chapter 2): the signer
# reviews exactly what they're certifying, chooses their certificate, proves
# who they are again (password, or single sign-on just now), and confirms.
class EntrySignaturesController < ApplicationController
  include AircraftScoped
  include EntrySigning
  before_action :set_entry

  def new
    prepare_signing(@entry)
  end

  def create
    sign_entry(@entry) do |signature|
      redirect_to aircraft_logbook_entry_path(@aircraft, @entry), notice: "Signed. #{EntrySignature::LABEL} #{signature.signer_name}, #{signature.certificate_label} #{signature.certificate_number}."
    end
  end

  private

  def set_entry = @entry = @aircraft.logbook_entries.find(params[:logbook_entry_id])
  def signing_page_path = new_aircraft_logbook_entry_signature_path(@aircraft, @entry)
end

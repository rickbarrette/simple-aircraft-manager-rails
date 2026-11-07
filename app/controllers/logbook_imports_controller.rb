# Upload scanned logbook pages (images or PDFs) as a document and, when an
# Anthropic API key is configured, have Claude transcribe them into logbook
# entries in the background (LogbookTranscriptionJob).
class LogbookImportsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!

  def new
    @collections = @aircraft.document_collections.ordered
  end

  def create
    files = Array(params[:pages]).compact_blank
    return redirect_to(new_aircraft_logbook_import_path(@aircraft), alert: "Choose the scanned pages to upload.") if files.empty?

    # Page order follows the file names ("page-002" before "page-010").
    files = files.sort_by { |f| f.original_filename.to_s.downcase.scan(/\d+|\D+/).map { _1.match?(/\d/) ? [ 0, _1.to_i ] : [ 1, _1 ] } }
    collection = find_or_build_collection
    document = @aircraft.documents.new(name: params[:document_name].presence || collection.name, doc_type: doc_type,
                                       document_collection: collection)
    document.pages.attach(files)
    unless collection.valid? && document.valid?
      @collections = @aircraft.document_collections.ordered
      flash.now[:alert] = (collection.errors.full_messages + document.errors.full_messages).to_sentence
      return render :new, status: :unprocessable_entity
    end

    import = nil
    ActiveRecord::Base.transaction do
      collection.save!
      document.save!
      import = @aircraft.logbook_imports.create!(user: current_user, document: document, log_type: params[:log_type],
                                                 transcribe: params[:transcribe] == "1" && LogbookImport.ai_available?)
    end
    log_event("document", "Logbook pages uploaded: #{document.name} (#{files.size} #{'page'.pluralize(files.size)})")
    LogbookTranscriptionJob.perform_later(import.id)
    redirect_to aircraft_logbook_import_path(@aircraft, import)
  end

  def show
    @import = @aircraft.logbook_imports.find(params[:id])
  end

  private

  def find_or_build_collection
    if params[:collection_id].present? && params[:collection_id] != "new"
      @aircraft.document_collections.find(params[:collection_id])
    else
      @aircraft.document_collections.new(name: params[:collection_name].presence || "Logbooks", visibility: "maintenance")
    end
  end

  def doc_type = Document::TYPES.key?(params[:doc_type]) ? params[:doc_type] : "LOG"
end

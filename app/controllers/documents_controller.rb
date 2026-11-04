class DocumentsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: %i[index show]
  before_action :set_document, only: %i[show edit update destroy]

  def index
    @collections = @aircraft.document_collections.ordered.includes(documents: { pages_attachments: :blob })
    @uncollected = @aircraft.documents.where(document_collection_id: nil).ordered.includes(pages_attachments: :blob)
  end

  def show
    @page = (params[:page] || 1).to_i.clamp(1, [ @document.pages.size, 1 ].max)
  end

  def new
    @document = @aircraft.documents.new(document_collection_id: params[:collection_id])
  end

  def create
    @document = @aircraft.documents.new(document_params)
    if @document.save
      log_event("document", "Document added: #{@document.name}")
      redirect_to aircraft_document_path(@aircraft, @document), notice: "Document added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    attrs = document_params
    new_pages = attrs.delete(:pages)
    @document.assign_attributes(attrs)
    @document.pages.attach(new_pages) if new_pages.present?
    Array(params[:remove_page_ids]).each { |id| @document.pages.find_by(id: id)&.purge_later }
    if @document.save
      log_event("document", "Document updated: #{@document.name}")
      redirect_to aircraft_document_path(@aircraft, @document), notice: "Document updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy!
    log_event("document", "Document deleted: #{@document.name}")
    redirect_to aircraft_documents_path(@aircraft), notice: "Document deleted."
  end

  private

  def set_document = @document = @aircraft.documents.find(params[:id])

  def document_params
    p = params.require(:document).permit(:name, :description, :doc_type, :visibility, :document_collection_id, pages: [])
    p[:pages]&.compact_blank!
    p.delete(:pages) if p[:pages].blank?
    p[:document_collection_id] = scoped_id(@aircraft.document_collections, p[:document_collection_id])
    p
  end
end

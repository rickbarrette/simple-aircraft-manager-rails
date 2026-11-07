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

  def bulk_new
    @bulk = bulk_defaults.merge(document_collection_id: params[:collection_id])
  end

  # Each file becomes a document named after it; files given the same name are
  # combined, in the order sent, as the pages of one document. Files arrive as
  # direct-upload signed ids (or as plain uploads when JavaScript is off).
  def bulk_create
    @bulk = bulk_defaults.merge(params.slice(:doc_type, :visibility, :document_collection_id, :new_collection).permit!.to_h.symbolize_keys)
    files = Array(params[:files]).compact_blank
    return bulk_error("Choose some files to upload.") if files.empty?
    return bulk_error("Upload at most #{MAX_BULK_FILES} files at a time.") if files.size > MAX_BULK_FILES

    names = Array(params[:names])
    rejected = []
    groups = {}
    files.each_with_index do |file, i|
      upload = file.is_a?(String) ? unattached_blob(file) : file
      next rejected << "file #{i + 1} (upload expired, try again)" unless upload
      name = names[i].to_s.squish.presence || File.basename(upload_filename(upload), ".*").tr("_", " ").squish.presence || "Untitled"
      (groups[name.first(255)] ||= []) << upload
    end

    collection_id, error = bulk_collection
    return bulk_error(error) if error
    created = []
    groups.each do |name, pages|
      doc = @aircraft.documents.new(name: name, doc_type: @bulk[:doc_type], visibility: @bulk[:visibility].presence,
                                    document_collection_id: collection_id, pages: pages)
      if doc.save
        created << doc
      else
        rejected << "#{name} (#{doc.errors.full_messages.to_sentence})"
        pages.each { _1.purge_later if _1.is_a?(ActiveStorage::Blob) }
      end
    end
    if created.empty?
      @aircraft.document_collections.find_by(id: collection_id)&.destroy if @bulk[:new_collection].present?
      return bulk_error("Nothing was uploaded: #{rejected.to_sentence}.")
    end

    log_event("document", "#{helpers.pluralize(created.size, 'document')} uploaded", notes: created.map(&:name).join(", ").truncate(1000))
    flash[:alert] = "Not uploaded: #{rejected.to_sentence}." if rejected.any?
    redirect_to aircraft_documents_path(@aircraft), notice: "#{helpers.pluralize(created.size, 'document')} uploaded.", status: :see_other
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

  MAX_BULK_FILES = 500

  def bulk_defaults = { doc_type: "OTHER", visibility: nil, document_collection_id: nil, new_collection: nil }

  def bulk_error(message)
    @bulk_error = message
    render :bulk_new, status: :unprocessable_entity
  end

  # A blob from a direct upload that hasn't been attached anywhere yet, so a
  # signed id lifted from an existing file's URL can't be re-attached here.
  def unattached_blob(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id)
    blob if blob && !blob.attachments.exists?
  end

  def upload_filename(upload)
    (upload.respond_to?(:original_filename) ? upload.original_filename : upload.filename).to_s
  end

  # [collection id or nil, error]: the chosen collection, or a new one.
  def bulk_collection
    return [ scoped_id(@aircraft.document_collections, @bulk[:document_collection_id]), nil ] if @bulk[:new_collection].blank?
    col = @aircraft.document_collections.create(name: @bulk[:new_collection].squish, visibility: @bulk[:visibility].presence || "private")
    col.persisted? ? [ col.id, nil ] : [ nil, "Couldn't create the collection: #{col.errors.full_messages.to_sentence}." ]
  end

  def set_document = @document = @aircraft.documents.find(params[:id])

  def document_params
    p = params.require(:document).permit(:name, :description, :doc_type, :visibility, :document_collection_id, pages: [])
    p[:pages]&.compact_blank!
    p.delete(:pages) if p[:pages].blank?
    p[:document_collection_id] = scoped_id(@aircraft.document_collections, p[:document_collection_id])
    p
  end
end

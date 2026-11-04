class DocumentCollectionsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!
  before_action :set_collection, only: %i[edit update destroy]

  def new
    @collection = @aircraft.document_collections.new
  end

  def create
    @collection = @aircraft.document_collections.new(collection_params)
    if @collection.save
      log_event("document", "Collection created: #{@collection.name}")
      redirect_to aircraft_documents_path(@aircraft), notice: "Collection created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @collection.update(collection_params)
      log_event("document", "Collection updated: #{@collection.name}")
      redirect_to aircraft_documents_path(@aircraft), notice: "Collection updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @collection.destroy!
    log_event("document", "Collection deleted: #{@collection.name}")
    redirect_to aircraft_documents_path(@aircraft), notice: "Collection and its documents deleted."
  end

  private

  def set_collection = @collection = @aircraft.document_collections.find(params[:id])
  def collection_params = params.require(:document_collection).permit(:name, :description, :visibility, :starred)
end

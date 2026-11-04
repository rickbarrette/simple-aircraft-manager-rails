class Admin::ComponentTypesController < ApplicationController
  before_action :require_admin!
  before_action :set_type, only: %i[edit update destroy]

  def index
    @component_types = ComponentType.ordered
  end

  def new
    @component_type = ComponentType.new
  end

  def create
    @component_type = ComponentType.new(type_params)
    if @component_type.save
      redirect_to admin_component_types_path, notice: "Component type created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @component_type.update(type_params)
      redirect_to admin_component_types_path, notice: "Component type updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @component_type.destroy
      redirect_to admin_component_types_path, notice: "Component type deleted."
    else
      redirect_to admin_component_types_path, alert: @component_type.errors.full_messages.to_sentence
    end
  end

  private

  def set_type = @component_type = ComponentType.find(params[:id])
  def type_params = params.require(:component_type).permit(:name, :consumable)
end

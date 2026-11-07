class Admin::LogbookTemplatesController < ApplicationController
  before_action :require_admin!
  before_action :set_template, only: %i[edit update destroy]

  def index
    LogbookTemplate.ensure_defaults!
    @templates = LogbookTemplate.ordered
  end

  def new
    @template = LogbookTemplate.new(position: (LogbookTemplate.maximum(:position) || 0) + 1)
  end

  def create
    @template = LogbookTemplate.new(template_params)
    if @template.save
      redirect_to admin_logbook_templates_path, notice: "Template added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @template.update(template_params)
      redirect_to admin_logbook_templates_path, notice: "Template updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy!
    redirect_to admin_logbook_templates_path, notice: "Template deleted."
  end

  def restore
    added = LogbookTemplate.restore_defaults!
    redirect_to admin_logbook_templates_path, notice: added.positive? ? "Restored #{helpers.pluralize(added, 'built-in template')}." : "All the built-in templates are already here."
  end

  private

  def set_template = @template = LogbookTemplate.find(params[:id])

  def template_params = params.require(:logbook_template).permit(:name, :reference, :text, :entry_type, :log_type, :certificate_type, :position)
end

class ComponentsController < ApplicationController
  include AircraftScoped
  before_action :require_owner!, except: %i[index show]
  before_action :set_component, only: %i[show edit update destroy reset_service]

  def index
    all = @aircraft.components.includes(:component_type, :parent_component).order(:install_location)
    @show_disposed = params[:disposed].present?
    all = all.where.not(status: "DISPOSED") unless @show_disposed
    # Depth-first tree order: parents followed by their children.
    by_parent = all.group_by(&:parent_component_id)
    @rows = []
    walk = ->(parent_id, depth) do
      (by_parent[parent_id] || []).sort_by { [ _1.component_type.name, _1.install_location.to_s ] }.each do |c|
        @rows << [ c, depth ]
        walk.(c.id, depth + 1)
      end
    end
    walk.(nil, 0)
    orphans = all.to_a - @rows.map(&:first) # children whose parent is filtered out
    orphans.each { @rows << [ _1, 0 ] }
  end

  def show
    @squawks = @component.squawks.by_priority.with_attached_attachments
  end

  def new
    @component = @aircraft.components.new(date_in_service: Date.current, status: "IN-USE",
                                          parent_component_id: params[:parent_id])
  end

  def create
    @component = @aircraft.components.new(component_params)
    if @component.save
      log_event("component", "Component added: #{@component}")
      redirect_to aircraft_components_path(@aircraft), notice: "Component added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @component.update(component_params)
      log_event("component", "Component updated: #{@component}")
      redirect_to aircraft_components_path(@aircraft), notice: "Component updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @component.destroy!
    log_event("component", "Component deleted: #{@component}")
    redirect_to aircraft_components_path(@aircraft), notice: "Component deleted."
  end

  # Always zeroes hours since overhaul; reset_in_service=1 also zeroes the
  # in-service clock (use when the part was physically replaced).
  def reset_service
    replaced = params[:reset_in_service] == "1"
    @component.reset_service!(reset_in_service: replaced)
    log_event("component", "#{replaced ? 'Replaced' : 'Serviced'}: #{@component}")
    redirect_to aircraft_components_path(@aircraft), notice: "#{@component} #{replaced ? 'replaced' : 'serviced'}."
  end

  private

  def set_component
    @component = @aircraft.components.find(params[:id])
  end

  def component_params
    params.require(:component).permit(
      :component_type_id, :parent_component_id, :manufacturer, :model, :serial_number,
      :install_location, :notes, :status, :date_in_service, :hours_in_service,
      :hours_since_overhaul, :overhaul_date, :tbo_hours, :tbo_days, :inspection_hours,
      :inspection_days, :replacement_hours, :replacement_days, :tbo_critical, :on_condition,
      :inspection_critical, :replacement_critical, :expires_on
    ).tap do |p|
      # Owners can create a component type inline instead of asking an admin.
      if (name = params[:new_component_type].to_s.strip).present?
        type = ComponentType.where("lower(name) = ?", name.downcase).first || ComponentType.create!(name: name)
        p[:component_type_id] = type.id
      end
    end
  end
end

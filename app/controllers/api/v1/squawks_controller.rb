module Api
  module V1
    # Squawks: list and report on an aircraft; find by external_ref; update.
    # Resolving happens through a signed logbook entry, not here.
    class SquawksController < BaseController
      before_action -> { require_scope!(:read) }, only: %i[index show lookup]
      before_action -> { require_scope!("squawks:write") }, :require_person!, only: %i[create update]

      # GET /aircraft/:aircraft_id/squawks?status=open|resolved|all (default open)
      def index
        scope = find_aircraft.squawks.includes(:reported_by).with_attached_attachments
        scope = case params.fetch(:status, "open")
        when "open" then scope.active
        when "resolved" then scope.resolved
        else scope
        end
        render_page(scope) { ApiPresenter.squawk(_1) }
      end

      # GET /squawks?external_ref=redmine:issue:4512
      def lookup
        ref = params.require(:external_ref)
        scope = Squawk.where(aircraft: aircraft_scope, external_ref: ref).includes(:reported_by).with_attached_attachments
        render json: { data: scope.map { ApiPresenter.squawk(_1) } }
      end

      def show
        render json: { data: ApiPresenter.squawk(find_squawk) }
      end

      # POST /aircraft/:aircraft_id/squawks
      def create
        aircraft = find_aircraft
        return not_permitted(:report_squawks) unless can?(:report_squawks, aircraft)
        squawk = aircraft.squawks.new(create_params.merge(reported_by: acting_user, resolved: false))
        squawk.component_id = nil unless aircraft.components.exists?(id: squawk.component_id)
        squawk.save!
        SquawkReported.call(squawk, by: acting_user)
        render json: { data: ApiPresenter.squawk(squawk) }, status: :created
      end

      # PATCH /squawks/:id: external_ref by anyone who may write; the rest
      # (issue, priority, component, notes) with "manage squawks", as in the app.
      def update
        squawk = find_squawk
        return render_error(:unprocessable_entity, "resolved", "A resolved squawk can't be changed.") if squawk.resolved?
        attrs = params.require(:squawk).permit(:external_ref, :issue_reported, :priority, :component_id, :notes)
        if (attrs.keys - %w[external_ref]).any? && !can?(:manage_squawks, squawk.aircraft)
          return not_permitted(:manage_squawks)
        end
        attrs[:component_id] = nil if attrs.key?(:component_id) && !squawk.aircraft.components.exists?(id: attrs[:component_id])
        squawk.update!(attrs)
        render json: { data: ApiPresenter.squawk(squawk) }
      end

      private

      def find_squawk = Squawk.where(aircraft: aircraft_scope).find(params[:id])

      def create_params
        params.require(:squawk).permit(:issue_reported, :priority, :component_id, :external_ref).tap do |p|
          p[:priority] = p.fetch(:priority, 2).to_i
        end
      end
    end
  end
end

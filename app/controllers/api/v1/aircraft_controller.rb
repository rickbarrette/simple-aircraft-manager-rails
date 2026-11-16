module Api
  module V1
    # The fleet this token reaches, and each aircraft's own lists.
    class AircraftController < BaseController
      before_action -> { require_scope!(:read) }

      def index
        render_page(aircraft_scope) { ApiPresenter.aircraft(_1) }
      end

      def show
        render json: { data: ApiPresenter.aircraft(find_aircraft(params[:id])) }
      end

      # The parts tree (?all=1 includes disposed parts).
      def components
        aircraft = find_aircraft(params[:id])
        scope = aircraft.components.includes(:component_type)
        scope = scope.where.not(status: "DISPOSED") unless params[:all].present?
        render_page(scope) { ApiPresenter.component(_1) }
      end

      # Everything coming due, soonest first (hours projected to dates).
      def due
        aircraft = find_aircraft(params[:id])
        render json: { data: DueList.new(aircraft).items.map { ApiPresenter.due_item(_1) } }
      end

      def inspections
        aircraft = find_aircraft(params[:id])
        render json: { data: Compliance.inspection_rows(aircraft).map { ApiPresenter.inspection(_1) } }
      end

      def ads
        aircraft = find_aircraft(params[:id])
        render json: { data: Compliance.ad_rows(aircraft).map { ApiPresenter.ad(_1) } }
      end

      # Logbook entries, oldest first (paged); ?log=AC|ENG|PROP|AVIONICS|OTHER, ?signed=true|false.
      def logbook_entries
        aircraft = find_aircraft(params[:id])
        scope = aircraft.logbook_entries.includes(:signature)
        scope = scope.where(log_type: params[:log]) if params[:log].present?
        scope = params[:signed] == "true" ? scope.where.associated(:signature) : scope.where.missing(:signature) if params[:signed].present?
        render_page(scope) { ApiPresenter.logbook_entry(_1) }
      end
    end
  end
end

# Admin → Integrations: tokens for other systems (e.g. Redmine), limited to
# chosen aircraft and scopes, each with an optional webhook (docs/api.md).
# The token and webhook secret are shown once, right after they're made.
class Admin::IntegrationsController < ApplicationController
  before_action :require_admin!
  before_action :set_integration, only: %i[show edit update destroy new_secret]

  def index
    @integrations = ApiToken.integration.order(revoked_at: :desc, name: :asc).includes(:webhook_endpoints)
  end

  def new
    @integration = ApiToken.new(kind: "integration", scopes: %w[read])
    @endpoint = WebhookEndpoint.new(events: [])
  end

  def create
    @integration = ApiToken.new(integration_params.merge(kind: "integration", user: current_user))
    @endpoint = build_endpoint(@integration)
    ApiToken.transaction do
      @integration.save!
      @endpoint&.save!
    end
    @secret = @endpoint&.secret
    render :created
  rescue ActiveRecord::RecordInvalid
    @endpoint ||= WebhookEndpoint.new(events: [])
    render :new, status: :unprocessable_entity
  end

  def show
    @endpoint = @integration.webhook_endpoints.first
    @deliveries = @endpoint ? @endpoint.deliveries.recent.limit(25) : []
  end

  def edit
    @endpoint = @integration.webhook_endpoints.first || WebhookEndpoint.new(events: [])
  end

  def update
    @endpoint = @integration.webhook_endpoints.first
    ApiToken.transaction do
      @integration.update!(integration_params)
      if webhook_params[:url].present?
        @endpoint ||= @integration.webhook_endpoints.new(secret: WebhookEndpoint.new_secret)
        @endpoint.update!(webhook_params)
      else
        @endpoint&.destroy!
      end
    end
    redirect_to admin_integration_path(@integration), notice: t("flash.admin_integrations.saved")
  rescue ActiveRecord::RecordInvalid
    @endpoint ||= WebhookEndpoint.new(events: [])
    render :edit, status: :unprocessable_entity
  end

  # A new webhook secret, shown once.
  def new_secret
    @endpoint = @integration.webhook_endpoints.first or return redirect_to(admin_integration_path(@integration))
    @endpoint.update!(secret: WebhookEndpoint.new_secret)
    @secret = @endpoint.secret
    render :created
  end

  def destroy
    @integration.revoke!
    @integration.webhook_endpoints.update_all(enabled: false)
    redirect_to admin_integrations_path, notice: t("flash.admin_integrations.revoked", name: @integration.name)
  end

  private

  def set_integration = @integration = ApiToken.integration.find(params[:id])

  def integration_params
    p = params.require(:api_token).permit(:name, scopes: [], aircraft_ids: [])
    p[:scopes] = Array(p[:scopes]) & ApiToken::SCOPES.keys
    p[:aircraft_ids] = Aircraft.where(id: Array(p[:aircraft_ids])).ids
    p
  end

  def webhook_params
    p = params.fetch(:webhook, {}).permit(:url, :enabled, events: [])
    p[:events] = Array(p[:events]) & WebhookEndpoint::EVENTS.keys
    p[:enabled] = p[:enabled] != "0"
    p
  end

  def build_endpoint(integration)
    return if webhook_params[:url].blank?
    integration.webhook_endpoints.new(webhook_params.merge(secret: WebhookEndpoint.new_secret))
  end
end

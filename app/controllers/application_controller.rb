class ApplicationController < ActionController::Base
  default_form_builder AppFormBuilder
  include Authentication
  allow_browser versions: :modern

  prepend_before_action :redirect_to_setup
  before_action { Current.ip_address = request.remote_ip } # for record history
  helper_method :current_user

  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found, layout: (authenticated? ? "application" : "public") }
      format.any { head :not_found }
    end
  end

  private

  def current_user = Current.user

  # First run: no users yet → create the initial admin.
  def redirect_to_setup
    redirect_to new_setup_path if !User.exists? && !is_a?(SetupController)
  end

  def require_admin!
    redirect_to root_path, alert: t("flash.application.admins_only") unless current_user&.admin?
  end
end

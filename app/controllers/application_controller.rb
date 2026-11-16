class ApplicationController < ActionController::Base
  default_form_builder AppFormBuilder
  include Authentication
  include TimeZones
  allow_browser versions: :modern

  include RejectsNullBytes
  prepend_before_action :redirect_to_setup
  before_action { Current.ip_address = request.remote_ip } # for record history
  helper_method :current_user

  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found, layout: (authenticated? ? "application" : "public") }
      format.any { head :not_found }
    end
  end

  # Asked for a format a page doesn't have (/aircraft/1/report.pdf): not a crash.
  rescue_from ActionView::MissingTemplate do |error|
    raise error if request.format.html?
    head :not_acceptable
  end

  # Input no form produces: a tampered upload reference, a number too big to
  # store, a missing required value or a link to a record that isn't there.
  # The forms validate what people can enter; this is the safety net.
  rescue_from ActiveSupport::MessageVerifier::InvalidSignature, ActiveModel::RangeError,
              ActiveRecord::NotNullViolation, ActiveRecord::InvalidForeignKey do |error|
    Rails.logger.warn("[input] #{error.class}: #{error.message.truncate(200)}")
    respond_to do |format|
      format.html { redirect_back_or_to root_path, alert: t("flash.application.invalid_input") }
      format.any { head :unprocessable_entity }
    end
  end

  private


  def current_user = Current.user

  # First run: no users yet → create the initial admin.
  def redirect_to_setup
    redirect_to new_setup_path if !User.exists? && !is_a?(SetupController)
  end

  # Adding or importing an aircraft (User#can_add_aircraft?).
  def require_aircraft_adder!
    redirect_to root_path, alert: t("flash.aircraft.ask_an_administrator") unless current_user.can_add_aircraft?
  end

  def require_admin!
    redirect_to root_path, alert: t("flash.application.admins_only") unless current_user&.admin?
  end
end

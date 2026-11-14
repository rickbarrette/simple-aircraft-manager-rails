class ApplicationController < ActionController::Base
  default_form_builder AppFormBuilder
  include Authentication
  include TimeZones
  allow_browser versions: :modern

  prepend_before_action :redirect_to_setup
  prepend_before_action :reject_null_bytes
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

  # No form sends a null byte; some libraries (password hashing, file paths)
  # raise on one, so refuse the request up front.
  def reject_null_bytes
    head :bad_request if contains_null_byte?(request.params)
  end

  def contains_null_byte?(value)
    case value
    when String then value.include?("\0")
    when Hash then value.any? { |k, v| contains_null_byte?(k) || contains_null_byte?(v) }
    when Array then value.any? { contains_null_byte?(_1) }
    else false
    end
  end

  def current_user = Current.user

  # First run: no users yet → create the initial admin.
  def redirect_to_setup
    redirect_to new_setup_path if !User.exists? && !is_a?(SetupController)
  end

  def require_admin!
    redirect_to root_path, alert: t("flash.application.admins_only") unless current_user&.admin?
  end
end

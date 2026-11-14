# Profile → Two-factor: set up an authenticator app (TOTP) for password and
# emailed-link sign-in, turn it off, or make new recovery codes.
class TwoFactorsController < ApplicationController
  rate_limit to: 10, within: 5.minutes, only: %i[create destroy recovery_codes], with: -> { redirect_to edit_profile_path(anchor: "two-factor"), alert: t("flash.two_factors.try_again_later") }

  def new
    return redirect_to(back_path, notice: t("flash.two_factors.two_factor_is_already")) if current_user.otp_enabled?
    session[:pending_otp_secret] ||= User.new_otp_secret
    @secret = session[:pending_otp_secret]
    svg = RQRCode::QRCode.new(User.otp_uri(@secret, current_user.email_address)).as_svg(module_size: 4, use_path: true, viewbox: true)
    @qr_data_uri = "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
  end

  def create
    secret = session[:pending_otp_secret]
    return redirect_to(new_two_factor_path(return_to: params[:return_to])) unless secret
    if User.valid_otp?(secret, params[:code])
      session.delete(:pending_otp_secret)
      @codes = current_user.enable_otp!(secret)
      log_security("turned on two-factor")
      render :codes
    else
      redirect_to new_two_factor_path(return_to: params[:return_to]), alert: t("flash.two_factors.that_code_didn_t")
    end
  end

  def recovery_codes
    return redirect_to(edit_profile_path(anchor: "two-factor"), alert: t("flash.two_factors.that_code_didn_t_2")) unless current_user.verify_second_factor(params[:code])
    @codes = current_user.enable_otp!(current_user.otp_secret)
    log_security("made new recovery codes")
    render :codes
  end

  def destroy
    return redirect_to(edit_profile_path(anchor: "two-factor"), alert: t("flash.two_factors.that_code_didn_t_3")) unless current_user.verify_second_factor(params[:code])
    current_user.disable_otp!
    log_security("turned off two-factor")
    redirect_to edit_profile_path(anchor: "two-factor"), notice: t("flash.two_factors.two_factor_is_off")
  end

  private

  # Back to a signing invitation the user came from, else the profile.
  def back_path = params[:return_to].to_s.match?(%r{\A/sign/[\w-]+\z}) ? params[:return_to] : edit_profile_path(anchor: "two-factor")
  helper_method :back_path

  def log_security(what) = Rails.logger.info("[auth] #{current_user.email_address} #{what}")
end

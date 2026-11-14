# The signing steps shared by aircraft users and invited signers.
module EntrySigning
  extend ActiveSupport::Concern

  private

  def signing_certificates = current_user.certificates.reject(&:expired?)

  def prepare_signing(entry)
    @certificates = signing_certificates
    session[:after_reauth] = signing_page_path # where single sign-on returns after signing in again
  end

  # Password re-entered now (with an authenticator code too, if the user has
  # one), or single sign-on completed in the last few minutes. Wrong
  # passwords and codes count toward the account lockout.
  def reauthenticated_method
    if params[:password].present?
      return if current_user.locked?
      unless current_user.authenticate_password(params[:password])
        current_user.register_failed_sign_in!
        return
      end
      return "password" unless current_user.otp_enabled?
      return "password_totp" if current_user.verify_second_factor(params[:otp_code])
      current_user.register_failed_sign_in!
      return
    elsif current_user.sso_uid? && (at = session[:reauthenticated_at]) && Time.zone.at(at) > EntrySigner::REAUTH_WINDOW.ago
      return "sso"
    end
    nil
  end

  def sign_entry(entry)
    certificate = current_user.certificates.find_by(id: params[:certificate_id])
    method = reauthenticated_method
    unless params[:confirm] == "1"
      return signing_failed(entry, t("flash.signing.confirm_box"))
    end
    unless method
      return signing_failed(entry, t("flash.signing.locked")) if current_user.reload.locked?
      return signing_failed(entry, t(current_user.otp_enabled? ? "flash.signing.reauth_otp" : "flash.signing.reauth", provider: Sso.label))
    end
    current_user.clear_failed_sign_ins!

    signature = EntrySigner.new(entry, user: current_user, certificate: certificate, auth_method: method, request: request).sign!
    session.delete(:reauthenticated_at)
    SignatureMailer.signed(signature).deliver_later if MailSettings.configured?
    yield signature
  rescue EntrySigner::Error => e
    signing_failed(entry, e.message)
  end

  def signing_failed(entry, message)
    prepare_signing(entry)
    @signing_error = message
    render :new, status: :unprocessable_entity
  end
end

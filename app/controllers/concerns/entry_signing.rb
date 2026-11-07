# The signing steps shared by aircraft users and invited signers.
module EntrySigning
  extend ActiveSupport::Concern

  private

  def signing_certificates = current_user.certificates.reject(&:expired?)

  def prepare_signing(entry)
    @certificates = signing_certificates
    session[:after_reauth] = signing_page_path # where single sign-on returns after signing in again
  end

  # Password re-entered now, or single sign-on completed in the last few minutes.
  def reauthenticated_method
    if params[:password].present?
      return "password" if current_user.authenticate_password(params[:password])
    elsif current_user.sso_uid? && (at = session[:reauthenticated_at]) && Time.zone.at(at) > EntrySigner::REAUTH_WINDOW.ago
      return "sso"
    end
    nil
  end

  def sign_entry(entry)
    certificate = current_user.certificates.find_by(id: params[:certificate_id])
    method = reauthenticated_method
    unless params[:confirm] == "1"
      return signing_failed(entry, "Tick the box to confirm you're signing this entry.")
    end
    return signing_failed(entry, "Re-enter your password (or sign in again with #{Sso.label}) to sign.") unless method

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

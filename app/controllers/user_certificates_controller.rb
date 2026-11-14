# The signed-in user's own certificates (Profile → Certificates).
class UserCertificatesController < ApplicationController
  before_action :set_certificate, only: %i[update destroy]

  def create
    certificate = current_user.certificates.new(certificate_params)
    back = safe_return_to || edit_profile_path(anchor: "certificates")
    if certificate.save
      redirect_to back, notice: t("flash.user_certificates.certificate_added", kind_label: certificate.kind_label)
    else
      redirect_to back, alert: t("flash.user_certificates.certificate_not_added", items: certificate.errors.full_messages.to_sentence)
    end
  end

  def update
    if @certificate.update(certificate_params)
      redirect_to edit_profile_path(anchor: "certificates"), notice: t("flash.user_certificates.certificate_updated")
    else
      redirect_to edit_profile_path(anchor: "certificates"), alert: t("flash.user_certificates.certificate_not_updated", items: @certificate.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @certificate.destroy!
    redirect_to edit_profile_path(anchor: "certificates"), notice: t("flash.user_certificates.certificate_removed")
  end

  private

  # Only back to a signing invitation page (no open redirects).
  def safe_return_to = params[:return_to].to_s.match?(%r{\A/sign/[\w-]+\z}) ? params[:return_to] : nil

  def set_certificate = @certificate = current_user.certificates.find(params[:id])

  def certificate_params = params.require(:user_certificate).permit(:kind, :number, :expires_on)
end

# The signed-in user's own certificates (Profile → Certificates).
class UserCertificatesController < ApplicationController
  before_action :set_certificate, only: %i[update destroy]

  def create
    certificate = current_user.certificates.new(certificate_params)
    if certificate.save
      redirect_to edit_profile_path(anchor: "certificates"), notice: "#{certificate.kind_label} certificate added."
    else
      redirect_to edit_profile_path(anchor: "certificates"), alert: "Certificate not added: #{certificate.errors.full_messages.to_sentence}."
    end
  end

  def update
    if @certificate.update(certificate_params)
      redirect_to edit_profile_path(anchor: "certificates"), notice: "Certificate updated."
    else
      redirect_to edit_profile_path(anchor: "certificates"), alert: "Certificate not updated: #{@certificate.errors.full_messages.to_sentence}."
    end
  end

  def destroy
    @certificate.destroy!
    redirect_to edit_profile_path(anchor: "certificates"), notice: "Certificate removed."
  end

  private

  def set_certificate = @certificate = current_user.certificates.find(params[:id])

  def certificate_params = params.require(:user_certificate).permit(:kind, :number, :expires_on)
end

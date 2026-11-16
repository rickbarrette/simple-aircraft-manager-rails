# The invited signer's side: sign in with their account for the invited
# address, add a certificate if needed, review the entry and sign it. The
# invitation gives access to that one entry only. It doesn't make accounts:
# only an administrator (or an administrator's invitation) does.
class InvitedSigningsController < ApplicationController
  include EntrySigning
  allow_unauthenticated_access only: :show
  before_action :set_invitation

  def show
    @entry = @invitation.logbook_entry
    @aircraft = @entry.aircraft
    unless authenticated?
      session[:return_to_after_authenticating] = request.url
      return render(:welcome)
    end
    return render(:wrong_account) unless current_user.email_address == @invitation.email
    return render(:signed) if @entry.signed?
    prepare_signing(@entry)
    render :new
  end

  def create
    @entry = @invitation.logbook_entry
    @aircraft = @entry.aircraft
    return render(:wrong_account) unless current_user.email_address == @invitation.email
    sign_entry(@entry) do |signature|
      @invitation.update!(used_at: Time.current, user: current_user)
      redirect_to invited_signing_path(params[:token]), notice: t("flash.invited_signings.signed", label: EntrySignature.label, signer_name: signature.signer_name, certificate_label: signature.certificate_label, certificate_number: signature.certificate_number)
    end
  end

  private

  def set_invitation
    @invitation = SigningInvitation.find_usable(params[:token])
    # Afterwards, the signer can still see what they signed.
    @invitation ||= SigningInvitation.where.not(used_at: nil).find_by(token_digest: SigningInvitation.digest(params[:token]), user: current_user) if current_user
    render(:expired, layout: "public", status: :not_found) unless @invitation
  end

  def current_user = Current.user || (resume_session && Current.user)
  def signing_page_path = invited_signing_path(params[:token])
end

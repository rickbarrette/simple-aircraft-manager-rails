# The invited signer's side: sign in (or create an account for the invited
# address), add a certificate if needed, review the entry and sign it. The
# invitation gives access to that one entry only.
class InvitedSigningsController < ApplicationController
  include EntrySigning
  allow_unauthenticated_access only: %i[show account]
  before_action :set_invitation
  rate_limit to: 10, within: 15.minutes, only: :account, with: -> { redirect_to new_session_path, alert: "Try again later." }

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

  # Creating an account for the invited email address.
  def account
    return redirect_to(invited_signing_path(params[:token])) if authenticated?
    if User.exists?(email_address: @invitation.email) || !Sso.password_login?
      return redirect_to invited_signing_path(params[:token]), alert: "Sign in to continue."
    end
    user = User.new(params.permit(:name, :password, :password_confirmation).merge(email_address: @invitation.email))
    if user.save
      reset_session
      start_new_session_for user
      redirect_to invited_signing_path(params[:token]), notice: "Account created. Add your certificate, then sign."
    else
      @entry = @invitation.logbook_entry
      @account_errors = user.errors.full_messages
      render :welcome, status: :unprocessable_entity
    end
  end

  def create
    @entry = @invitation.logbook_entry
    @aircraft = @entry.aircraft
    return render(:wrong_account) unless current_user.email_address == @invitation.email
    sign_entry(@entry) do |signature|
      @invitation.update!(used_at: Time.current, user: current_user)
      redirect_to invited_signing_path(params[:token]), notice: "Signed. #{EntrySignature::LABEL} #{signature.signer_name}, #{signature.certificate_label} #{signature.certificate_number}."
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

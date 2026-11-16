# Opening an invitation link (AccessInvitation): see what it gives, then sign
# in and accept. Only an administrator's invitation can make a new account
# (with a password here, or by signing in with SSO: SsoController); others
# need an existing one. An invitation for one email address only works for
# that address. Any invalid link (unknown, expired, used up, revoked) gets
# one answer.
class JoinsController < ApplicationController
  allow_unauthenticated_access only: %i[show account]
  before_action :set_invitation
  rate_limit to: 10, within: 15.minutes, only: %i[account accept],
             with: -> { redirect_to join_path(params[:token]), alert: t("flash.joins.try_again_later") }

  def show
    unless current_user
      session[:return_to_after_authenticating] = request.url
      session[:join_token] = params[:token] # for an account made by signing in with SSO
      return render(:welcome)
    end
    return redirect_to(root_path, notice: t("flash.joins.already_accepted")) if @invitation.redeemed_by?(current_user)
    return render(:wrong_account) unless @invitation.for?(current_user)
    render :accept
  end

  # A new account, then the invitation accepted with it.
  def account
    return redirect_to(join_path(params[:token])) if current_user
    unless Sso.password_login? && @invitation.creates_accounts?
      return redirect_to(join_path(params[:token]), alert: t("flash.joins.sign_in_to_continue"))
    end
    email = @invitation.email || params[:email_address].to_s.strip.downcase
    if User.exists?(email_address: email)
      return redirect_to join_path(params[:token]), alert: t("flash.joins.account_exists")
    end
    user = User.new(params.permit(:name, :password, :password_confirmation).merge(email_address: email))
    results = nil
    User.transaction do
      raise ActiveRecord::Rollback unless user.save
      results = @invitation.redeem!(user)
    end
    if results
      reset_session
      start_new_session_for user
      redirect_to root_path, notice: [ t("flash.joins.welcome"), AccessInvitation.describe(results) ].join(" ").strip
    else
      @account_errors = user.errors.full_messages
      render :welcome, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :invalid, layout: "public", status: :not_found
  end

  def accept
    return redirect_to(root_path, notice: t("flash.joins.already_accepted")) if @invitation.redeemed_by?(current_user)
    return render(:wrong_account) unless @invitation.for?(current_user)
    redirect_to root_path, notice: [ t("flash.joins.accepted"), AccessInvitation.describe(@invitation.redeem!(current_user)) ].join(" ").strip
  rescue ActiveRecord::RecordInvalid
    render :invalid, layout: "public", status: :not_found
  end

  private

  def set_invitation
    @invitation = AccessInvitation.find_by_token(params[:token])
    render :invalid, layout: "public", status: :not_found unless @invitation&.usable?
  end

  def current_user = Current.user || (resume_session && Current.user)
end

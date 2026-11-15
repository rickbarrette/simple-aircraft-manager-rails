# Profile → API tokens: personal tokens for the REST API (docs/api.md). The
# token is shown once, on the page right after it's made (not kept in the
# flash or anywhere else).
class ApiTokensController < ApplicationController
  def create
    @token = current_user.api_tokens.new(name: params.dig(:api_token, :name), kind: "personal",
                                         scopes: Array(params.dig(:api_token, :scopes)) & ApiToken::SCOPES.keys)
    if @token.save
      render :created
    else
      redirect_to edit_profile_path(anchor: "api"), alert: @token.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.api_tokens.personal.active.find(params[:id]).revoke!
    redirect_to edit_profile_path(anchor: "api"), notice: t("flash.api_tokens.revoked")
  end
end

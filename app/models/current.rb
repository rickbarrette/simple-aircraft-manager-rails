class Current < ActiveSupport::CurrentAttributes
  # api_token / api_user: an API request (see Api::V1::BaseController), which
  # acts as a person without a browser session.
  attribute :session, :ip_address, :api_token, :api_user

  def user = api_user || session&.user
end

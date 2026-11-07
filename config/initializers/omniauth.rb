# OpenID Connect single sign-on; see app/models/sso.rb for the settings.
# The provider is registered at boot, so changing OIDC_* needs a restart.
Rails.application.config.middleware.use OmniAuth::Builder do
  if (ENV["OIDC_ISSUER"].present? && ENV["OIDC_CLIENT_ID"].present?) || Rails.env.test?
    app_url = ENV["APP_URL"].presence&.chomp("/") ||
              "#{ENV.fetch('FORCE_SSL', 'true') == 'true' ? 'https' : 'http'}://#{ENV.fetch('APP_HOST', 'localhost:3000')}"
    provider :openid_connect,
             name: :oidc,
             issuer: ENV["OIDC_ISSUER"],
             discovery: true,
             scope: %i[openid email profile],
             response_type: :code,
             pkce: true,
             # "prompt=login" makes the provider ask again (signing an entry).
             allow_authorize_params: %i[prompt],
             client_options: {
               identifier: ENV["OIDC_CLIENT_ID"],
               secret: ENV["OIDC_CLIENT_SECRET"],
               redirect_uri: "#{app_url}/auth/oidc/callback"
             }
  end
end

OmniAuth.config.allowed_request_methods = [ :post ] # sign-in starts from a CSRF-protected form
# Build callback URLs from the configured address, never the request's Host header.
# (Tests run on www.example.com, so they keep the default.)
unless Rails.env.test?
  OmniAuth.config.full_host = ENV["APP_URL"].presence&.chomp("/") ||
                              "#{ENV.fetch('FORCE_SSL', 'true') == 'true' ? 'https' : 'http'}://#{ENV.fetch('APP_HOST', 'localhost:3000')}"
end
OmniAuth.config.logger = Rails.logger

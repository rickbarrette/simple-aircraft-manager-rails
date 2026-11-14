# Single sign-on through an OpenID Connect provider (Authentik, Keycloak,
# Google…), configured with environment variables:
#
#   OIDC_ISSUER           issuer URL, e.g. https://auth.example.com/application/o/sam/
#   OIDC_CLIENT_ID        client ID
#   OIDC_CLIENT_SECRET    client secret
#   OIDC_PROVIDER_NAME    button label (default "SSO")
#   OIDC_AUTO_CREATE_USERS  "true" to create an account for anyone the
#                         provider lets through (they start with no aircraft)
#   OIDC_TRUST_EMAIL      "true" to link existing accounts by email even when
#                         the provider doesn't mark the email verified. Only
#                         for providers where users can't change their email.
#   OIDC_ADMIN_GROUP      members of this group are admins, others aren't
#                         (synced at each sign-in; needs a "groups" claim)
#   PASSWORD_LOGIN        "false" to turn off email/password sign-in once SSO works
#   APP_URL               public base URL (default https://APP_HOST)
module Sso
  PROVIDER = :oidc

  module_function

  def enabled? = ENV["OIDC_ISSUER"].present? && ENV["OIDC_CLIENT_ID"].present?
  def label = ENV["OIDC_PROVIDER_NAME"].presence || "SSO"
  def auto_create_users? = ENV["OIDC_AUTO_CREATE_USERS"] == "true"
  def trust_email? = ENV["OIDC_TRUST_EMAIL"] == "true"
  def admin_group = ENV["OIDC_ADMIN_GROUP"].presence

  # Password sign-in stays on unless SSO is set up and it's switched off, so
  # a broken SSO setup can't lock everyone out.
  def password_login? = !enabled? || ENV["PASSWORD_LOGIN"] != "false"

  def app_url
    ENV["APP_URL"].presence&.chomp("/") ||
      "#{ENV.fetch('FORCE_SSL', 'true') == 'true' ? 'https' : 'http'}://#{ENV.fetch('APP_HOST', 'localhost:3000')}"
  end
end

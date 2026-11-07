# Content Security Policy: scripts only from this site, plus inline scripts
# carrying the per-session nonce (the theme snippet, the importmap, Chartkick).
# Inline style attributes stay allowed (Chartkick sizes and a few views use them).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :blob
    policy.font_src :self, :data
    policy.connect_src :self
    policy.media_src :self, :blob
    policy.frame_src :self # PDFs in the document viewer
    policy.worker_src :self
    policy.manifest_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :self
    # Signing in with SSO posts here, then redirects to the provider.
    policy.form_action(*[ :self, (ENV["OIDC_ISSUER"].present? ? ENV["OIDC_ISSUER"][%r{\Ahttps?://[^/]+}i] : nil) ].compact)
  end

  # Stable for a session, so pages Turbo swaps in keep matching the policy
  # the browser got with the first page load.
  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end

# Uploaded files are served as they are (PDFs need the browser's viewer);
# dangerous types are already sent as downloads, with nosniff.
Rails.application.config.to_prepare do
  ActiveStorage::BaseController.content_security_policy false
end

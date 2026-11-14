require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Set FORCE_SSL=false when serving plain HTTP (e.g. on a home LAN without a TLS proxy).
  config.assume_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost"),
    protocol: ENV.fetch("FORCE_SSL", "true") == "true" ? "https" : "http"
  }
  # Email (password resets, sign-in links). Configure SMTP_ADDRESS (and friends)
  # to enable; Admin → About has a test button.
  if ENV["SMTP_ADDRESS"].present?
    smtp_port = ENV.fetch("SMTP_PORT", 587).to_i
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: smtp_port,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: (:plain if ENV["SMTP_USERNAME"].present?),
      # Port 465 is TLS from the start; others upgrade with STARTTLS.
      tls: ENV.fetch("SMTP_TLS") { smtp_port == 465 ? "true" : "false" } == "true",
      enable_starttls_auto: true,
      open_timeout: 10,
      read_timeout: 15
    }.compact
  end

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Answer only for the app's own names (stops DNS rebinding and forged Host
  # headers): APP_HOST, the APP_URL host, ALLOWED_HOSTS, localhost and IP
  # addresses (a rebinding attack needs a name). Off when APP_HOST isn't set.
  if ENV["APP_HOST"].present?
    config.hosts = [
      ENV["APP_HOST"].sub(/:\d+\z/, ""),
      (URI.parse(ENV["APP_URL"]).host if ENV["APP_URL"].present?),
      *ENV.fetch("ALLOWED_HOSTS", "").split(",").map(&:strip),
      "localhost",
      IPAddr.new("0.0.0.0/0"),
      IPAddr.new("::/0")
    ].compact_blank
    config.host_authorization = {
      exclude: ->(request) { request.path == "/up" },
      # Say why, rather than a blank page: usually a name that's simply missing.
      response_app: ->(env) {
        host = ActionDispatch::Request.new(env).host.to_s.gsub(/[^a-z0-9.\-:\[\]]/i, "").first(253)
        [ 403, { "content-type" => "text/plain; charset=utf-8" },
          [ "This server doesn't answer for \"#{host}\". If that's a name for this app, add it to ALLOWED_HOSTS (comma-separated) and restart.\n" ] ]
      }
    }
  end
end

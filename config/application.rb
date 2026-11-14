require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SimpleAircraftManager
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Language: every config/locales/<locale>.yml is available; APP_LOCALE
    # picks one (default English). Strings it lacks fall back to English.
    config.i18n.available_locales = Dir[File.join(__dir__, "locales", "*.yml")].map { File.basename(_1, ".yml").to_sym }
    config.i18n.default_locale = ENV.fetch("APP_LOCALE", "en").to_sym
    config.i18n.fallbacks = [ :en ]

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[active_storage assets tasks])

    # File links (rails_blob_path) stop working after this, so a link copied
    # from a page, or seen before access was removed, doesn't work forever.
    config.active_storage.urls_expire_in = 1.hour

    config.action_dispatch.default_headers.merge!(
      "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()",
      "Cross-Origin-Opener-Policy" => "same-origin"
    )

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Small resized copies of photos (squawk thumbnails), made with libvips.
    config.active_storage.variant_processor = :vips
  end
end

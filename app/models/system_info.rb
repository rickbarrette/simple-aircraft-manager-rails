# What the admin About page shows: versions, configuration (never secrets)
# and a health summary of the database, file storage and background jobs.
class SystemInfo
  KEY_GEMS = %w[
    puma thruster propshaft importmap-rails turbo-rails stimulus-rails tailwindcss-rails tailwindcss-ruby
    solid_queue solid_cache sqlite3 chartkick commonmarker anthropic
    omniauth omniauth_openid_connect rubyzip roo pdf-reader bcrypt
  ].freeze

  # Where the source lives; APP_REPOSITORY_URL overrides it for a fork.
  REPOSITORY_URL = ENV["APP_REPOSITORY_URL"].presence || "https://github.com/rickbarrette/simple-aircraft-manager-rails"

  DATABASES = %i[primary cache queue].freeze

  # The release version, YYYY.MM.N (the repository's VERSION file).
  def version
    @version ||= Rails.root.join("VERSION").then { _1.exist? ? _1.read.strip.presence : nil } || "unreleased"
  end

  # "2026.11.0 (build 87e3094)"
  def version_label = t(:version_label, version: version, revision: revision)

  # The build: the commit it was made from. Set by the Docker build (see
  # Dockerfile); in development, read from git.
  def revision
    @revision ||= ENV["APP_REVISION"].presence ||
                  (Rails.root.join(".git").exist? && `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip.presence) ||
                  "unknown"
  end

  # Only an http(s) address is linked (it comes from the environment).
  def repository_url = REPOSITORY_URL.match?(%r{\Ahttps?://[^\s"'<>]+\z}) ? REPOSITORY_URL.chomp("/") : nil

  # The running commit on the repository host, when the revision is known.
  def revision_url
    "#{repository_url}/commit/#{revision}" if repository_url && revision.match?(/\A\h{7,40}\z/)
  end

  def built_at
    Time.zone.parse(ENV["APP_BUILT_AT"].to_s) if ENV["APP_BUILT_AT"].present?
  rescue ArgumentError
    nil
  end

  def booted_at = Rails.application.config.x.booted_at

  def runtime
    {
      "Ruby" => "#{RUBY_VERSION}p#{RUBY_PATCHLEVEL} (#{RUBY_PLATFORM})",
      "YJIT" => t(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? :on : :off),
      "Rails" => Rails.version,
      "SQLite" => SQLite3::SQLITE_VERSION,
      "Bundler" => Bundler::VERSION,
      t(:environment) => Rails.env,
      t(:time_zone) => Time.zone.name
    }
  end

  def key_gems
    KEY_GEMS.filter_map { |name| (spec = specs[name]) && [ name, spec.version.to_s ] }
  end

  def all_gems = specs.values.sort_by(&:name).map { [ _1.name, _1.version.to_s ] }

  # Configured or not; secret values are never read out.
  def features
    {
      t(:sso) => Sso.enabled? ? (Sso.password_login? ? Sso.label : t(:sso_only, provider: Sso.label)) : t(:not_configured),
      t(:transcription) => ENV["ANTHROPIC_API_KEY"].present? ? t(:on_with, detail: LogbookTranscriber::MODEL) : t(:no_api_key),
      t(:email) => MailSettings.configured? ? ActionMailer::Base.delivery_method.to_s.upcase : t(:not_configured),
      t(:upload_limit) => t(:upload_limit_value, mb: Setting.max_upload_mb),
      t(:https) => t(Rails.application.config.force_ssl ? :yes : :no),
      t(:file_storage) => ActiveStorage::Blob.service.class.name.demodulize.delete_suffix("Service")
    }
  end

  def databases
    DATABASES.filter_map do |name|
      label = I18n.t(name, scope: "models.system_info.databases")
      config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name.to_s)
      next unless config
      path = Rails.root.join(config.database.to_s)
      [ label, path.exist? ? Dir["#{path}*"].sum { File.size(_1) } : nil ]
    end
  end

  def record_counts
    { t(:users) => User.count, t(:aircraft) => Aircraft.count, t(:documents) => Document.count,
      t(:logbook_entries) => LogbookEntry.count, t(:flights) => FlightLog.count, t(:squawks) => Squawk.count }
  end

  # Bytes saved by storing identical files once, estimated from checksums.
  def storage
    blobs = ActiveStorage::Blob
    total = blobs.sum(:byte_size)
    unique = blobs.group(:checksum).maximum(:byte_size).values.sum
    { files: blobs.count, bytes: total, shared_bytes: total - unique, free_bytes: free_disk_bytes }
  end

  def jobs
    return unless defined?(SolidQueue) && SolidQueue::Job.table_exists?
    {
      workers: SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).count,
      ready: SolidQueue::ReadyExecution.count,
      scheduled: SolidQueue::ScheduledExecution.count,
      failed: SolidQueue::FailedExecution.count
    }
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  private

  def t(key, **opts) = I18n.t(key, scope: "models.system_info", **opts)

  def specs = Gem.loaded_specs

  def free_disk_bytes
    root = ActiveStorage::Blob.service.try(:root) or return
    line = IO.popen([ "df", "-Pk", root.to_s ], err: File::NULL, &:read).lines.last
    line.split[3].to_i * 1024 if line
  rescue SystemCallError
    nil
  end
end

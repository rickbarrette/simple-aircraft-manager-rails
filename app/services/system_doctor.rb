require "net/http"
require "socket"
require "open3"

# A health report for the installation (bin/rails sam:doctor): settings,
# connections to email, single sign-on and Google Drive, migrations, disk
# space, background jobs, and how recent the backups, checks and audit are.
class SystemDoctor
  Check = Data.define(:status, :name, :detail) # status: :ok, :warn, :fail

  def checks
    [ secret_key, host, https, email, sso, password_login, migrations, disk, jobs, backup, integrity, offsite, procedures, audit ].flatten.compact
  end

  def self.report
    doctor = new
    list = doctor.checks
    lines = list.map { |c| "#{{ ok: '  ok ', warn: ' WARN', fail: ' FAIL' }[c.status]}  #{c.name.ljust(22)} #{c.detail}" }
    [ "Simple Aircraft Manager #{SystemInfo.new.version_label} (#{Rails.env})", *lines ].join("\n").then { [ _1, list ] }
  end

  private

  def ok(name, detail) = Check.new(:ok, name, detail)
  def warning(name, detail) = Check.new(:warn, name, detail)
  def failed(name, detail) = Check.new(:fail, name, detail)
  def production? = Rails.env.production?

  def secret_key
    return ok("Secret key", "development/test key") unless production?
    return warning("Secret key", "SECRET_KEY_BASE isn't set in the environment") if ENV["SECRET_KEY_BASE"].blank? && ENV["RAILS_MASTER_KEY"].blank?
    return ok("Secret key", "set (keep a copy off the server)") if ENV["SECRET_KEY_BASE"].blank?
    case SecretKeyCheck.strength
    when :ok then ok("Secret key", "set (keep a copy off the server)")
    else failed("Secret key", "only #{ENV['SECRET_KEY_BASE'].length} characters: replace it with the output of bin/rails secret")
    end
  end

  def host
    url = Sso.app_url
    production? && ENV["APP_HOST"].blank? && ENV["APP_URL"].blank? ? warning("Address", "APP_HOST/APP_URL not set: email links point at #{url}") : ok("Address", url)
  end

  def https = Rails.application.config.force_ssl ? ok("HTTPS", "enforced (FORCE_SSL)") : warning("HTTPS", "not enforced by the app (FORCE_SSL=false): only behind a TLS proxy or on a private network")

  def email
    return warning("Email", "not configured (set SMTP_ADDRESS): no password resets, sign-in links or alerts") unless MailSettings.configured?
    s = ActionMailer::Base.smtp_settings
    return ok("Email", "#{ActionMailer::Base.delivery_method} delivery") unless ActionMailer::Base.delivery_method == :smtp
    Socket.tcp(s[:address], s[:port], connect_timeout: 5).close
    ok("Email", "SMTP #{s[:address]}:#{s[:port]} reachable (send one with bin/rails \"email:test[you@example.com]\")")
  rescue StandardError => e
    failed("Email", "can't reach SMTP #{s[:address]}:#{s[:port]} (#{e.class.name.demodulize})")
  end

  def sso
    return unless Sso.enabled?
    uri = URI("#{ENV['OIDC_ISSUER'].to_s.chomp('/')}/.well-known/openid-configuration")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) { _1.get(uri.request_uri) }
    res.is_a?(Net::HTTPSuccess) ? ok("Single sign-on", "#{Sso.label} issuer reachable") : failed("Single sign-on", "#{uri} answered #{res.code}")
  rescue StandardError => e
    failed("Single sign-on", "can't reach #{Sso.label} (#{e.class.name.demodulize}: #{e.message.truncate(80)})")
  end

  def password_login
    return ok("Password sign-in", "on") if Sso.password_login?
    ok("Password sign-in", "off (single sign-on only; invited mechanics can't create accounts)")
  end

  def migrations
    pending = ActiveRecord::Base.connection_pool.migration_context.needs_migration?
    pending ? failed("Database", "migrations pending: run bin/rails db:migrate (or restart the container)") : ok("Database", "schema up to date")
  end

  def disk
    out = Open3.capture2("df", "-Pk", Rails.root.join("storage").to_s).first.lines.last.to_s.split
    return warning("Disk space", "couldn't check") if out.size < 5
    free_gb = out[3].to_f / 1024 / 1024
    used = out[4].to_i
    detail = "#{free_gb.round(1)} GB free on the storage volume (#{used}% used)"
    free_gb < 1 || used > 95 ? failed("Disk space", detail) : (free_gb < 5 || used > 85 ? warning("Disk space", detail) : ok("Disk space", detail))
  end

  def jobs
    return unless defined?(SolidQueue::Process)
    count = SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).count
    count.positive? ? ok("Background jobs", "#{count} running (nightly backup, reminders, AD search)") : warning("Background jobs", "none seen in the last 5 minutes: is the app running with SOLID_QUEUE_IN_PUMA?")
  rescue StandardError => e
    warning("Background jobs", "couldn't check (#{e.class.name.demodulize})")
  end

  def backup = age_check("Last backup", BackupRun.order(:created_at).last) { "#{_1.ok ? 'ok' : 'FAILED'}: #{_1.message.to_s.truncate(70)}" }
  def integrity = age_check("Records check", IntegrityCheck.order(:created_at).last) { _1.ok ? "no problems" : "#{Array(_1.problems).size} problem(s)" }

  def offsite
    return warning("Off-site backup", "Google Drive not connected (Admin → Off-site Backup), or describe another off-site copy in the procedures") unless OffsiteConnection.connected?
    OffsiteConnection.current.client.account_email
    run = OffsiteRun.latest_backup
    run ? age_check("Off-site backup", run) { "#{_1.ok ? 'ok' : 'FAILED'}: Google Drive #{OffsiteConnection.current.account_email}" } : warning("Off-site backup", "Google Drive connected; no copy yet")
  rescue GoogleDriveClient::Error => e
    failed("Off-site backup", "Google Drive: #{e.message.truncate(90)}")
  end

  def procedures
    r = ProceduresRevision.current
    r ? ok("Procedures", "revision #{r.number}, adopted #{r.adopted_at.to_date}") : warning("Procedures", "not adopted (Admin → Recordkeeping Procedures)")
  end

  def audit
    return warning("Records audit", "never done (Admin → Records Audits)") unless AuditRun.latest
    due = AuditRun.next_due
    detail = "next due #{due} (last #{AuditRun.latest.performed_at.to_date})"
    due < Date.current ? warning("Records audit", "overdue: #{detail}") : ok("Records audit", detail)
  end

  def age_check(name, record)
    return warning(name, "never run") unless record
    detail = "#{record.created_at.to_date}, #{yield(record)}"
    return failed(name, detail) unless record.ok
    record.created_at < 2.days.ago ? warning(name, "#{detail} (more than 2 days ago)") : ok(name, detail)
  end
end

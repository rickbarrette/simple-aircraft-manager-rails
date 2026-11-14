# Whether the app can send email, and a secret-free description of how.
module MailSettings
  module_function

  # Production only sends with SMTP_ADDRESS set; dev and test use their own
  # delivery methods.
  def configured?
    ActionMailer::Base.delivery_method != :smtp || ENV["SMTP_ADDRESS"].present?
  end

  def summary
    method = ActionMailer::Base.delivery_method
    t = ->(key, **opts) { I18n.t(key, scope: "models.mail_settings", **opts) }
    rows = { t.(:delivery) => configured? ? method.to_s.upcase : t.(:not_configured) }
    if method == :smtp && configured?
      s = ActionMailer::Base.smtp_settings
      rows[t.(:server)] = "#{s[:address]}:#{s[:port]}"
      rows[t.(:encryption)] = s[:tls] ? "TLS" : t.(:starttls)
      rows[t.(:signs_in_as)] = s[:user_name].presence || t.(:no_login)
    end
    rows[t.(:from)] = ApplicationMailer.default[:from]
    rows
  end
end

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
    rows = { "Delivery" => configured? ? method.to_s.upcase : "not configured (set SMTP_ADDRESS)" }
    if method == :smtp && configured?
      s = ActionMailer::Base.smtp_settings
      rows["Server"] = "#{s[:address]}:#{s[:port]}"
      rows["Encryption"] = s[:tls] ? "TLS" : "STARTTLS when offered"
      rows["Signs in as"] = s[:user_name].presence || "no login"
    end
    rows["From"] = ApplicationMailer.default[:from]
    rows
  end
end

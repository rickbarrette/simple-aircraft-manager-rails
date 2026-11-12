class ApplicationMailer < ActionMailer::Base
  helper ApplicationHelper # fmt_date etc. in emails
  default from: ENV.fetch("MAIL_FROM", "aircraft-manager@localhost")
  layout "mailer"
end

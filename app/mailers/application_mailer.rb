class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "aircraft-manager@localhost")
  layout "mailer"
end

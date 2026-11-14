# Tells the signer their signature was affixed (AC 120-78B 2.2.3).
class SignatureMailer < ApplicationMailer
  def signed(signature)
    @signature = signature
    @entry = signature.logbook_entry
    mail subject: t(".subject", tail_number: @entry.aircraft.tail_number), to: signature.signer_email
  end
end

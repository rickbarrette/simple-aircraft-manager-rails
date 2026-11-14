# Signs a logbook entry for a user with one of their certificates
# (AC 120-78B 2.1.2 / 2.2): the entry's signer fields are set from the
# certificate, then the signature records exactly what was signed. Signing a
# correction marks the entry it corrects as superseded (2.2.8).
class EntrySigner
  REAUTH_WINDOW = 5.minutes

  class Error < StandardError; end

  def initialize(entry, user:, certificate:, auth_method:, request: nil)
    @entry = entry
    @user = user
    @certificate = certificate
    @auth_method = auth_method
    @request = request
  end

  def sign!
    raise Error, I18n.t("services.entry_signer.your_account_is_disabled") if @user.disabled?
    raise Error, I18n.t("services.entry_signer.that_certificate_isn_t_yours") unless @certificate && @certificate.user_id == @user.id
    problems = @entry.signing_problems(@certificate)
    raise Error, I18n.t("services.entry_signer.this_entry_can_t_be", to_sentence: problems.to_sentence) if problems.any?

    LogbookEntry.transaction do
      @entry.update!(signoff_person: @user.display_name, signoff_certificate_type: @certificate.kind,
                     signoff_certificate_number: @certificate.number)
      @entry.reload
      signature = @entry.create_signature!(
        user: @user, signer_name: @user.display_name, signer_email: @user.email_address,
        certificate_kind: @certificate.kind, certificate_number: @certificate.number,
        statement: @entry.certification_statement(@certificate.kind), signed_at: Time.current,
        content_digest: @entry.content_digest, content_snapshot: @entry.content_snapshot.to_json,
        auth_method: @auth_method, ip_address: @request&.remote_ip, user_agent: @request&.user_agent.to_s.first(255)
      )
      @entry.supersedes&.update_column(:superseded_at, signature.signed_at)
      @entry.aircraft.log_event!("logbook", "Logbook entry signed electronically (#{@entry.date})",
                                 notes: I18n.t("services.entry_signer.text", signer_name: signature.signer_name, certificate_label: signature.certificate_label, certificate_number: signature.certificate_number), user: @user)
      signature
    end
  end
end

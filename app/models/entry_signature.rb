# An electronic signature on a logbook entry (AC 120-78B chapter 2).
#
# It records the signer, the certificate they signed with, the statement they
# certified, when, and how they proved who they were. content_digest is a
# SHA-256 of the entry's content at signing (content_snapshot is that content),
# so any later change shows; seal is an HMAC over the signature itself, keyed
# by this server, so the signature record can't be altered unnoticed either.
class EntrySignature < ApplicationRecord
  include Versioned
  AUTH_METHODS = { "password" => "password re-entered", "password_totp" => "password and authenticator code re-entered",
                   "sso" => "single sign-on, signed in again" }.freeze
  # "Certified by" conveys the intent to sign (2.2.2).
  LABEL = "Certified by".freeze

  belongs_to :logbook_entry
  belongs_to :user, optional: true

  validates :signer_name, :certificate_kind, :certificate_number, :statement, :signed_at, :content_digest, :content_snapshot, presence: true
  validates :auth_method, inclusion: { in: AUTH_METHODS.keys + [ "imported" ] }
  validates :logbook_entry_id, uniqueness: true
  before_create { self.seal ||= compute_seal unless imported? }
  before_update { throw :abort } # signatures are permanent (2.1.2.7)
  before_destroy { throw :abort unless destroyed_by_association }

  def self.seal_key = Rails.application.key_generator.generate_key("entry-signature-seal", 32)

  def imported? = origin.present?
  def certificate_label = UserCertificate::SHORT_LABELS.fetch(certificate_kind, certificate_kind)

  def compute_seal
    payload = [ logbook_entry_id, user_id, signer_name, certificate_kind, certificate_number, statement,
                signed_at.utc.iso8601(6), content_digest, auth_method ].join("\u001f")
    OpenSSL::HMAC.hexdigest("SHA256", self.class.seal_key, payload)
  end

  def seal_valid? = imported? || (seal.present? && ActiveSupport::SecurityUtils.secure_compare(seal, compute_seal))
  def content_matches? = content_digest == logbook_entry.content_digest

  # :valid, :superseded, :altered (content or signature changed since signing)
  def status
    return :altered unless seal_valid? && content_matches?
    logbook_entry.superseded_at ? :superseded : :valid
  end

  def status_label
    { valid: "Valid", superseded: "Superseded by a correction", altered: "Altered since signing" }[status]
  end
end

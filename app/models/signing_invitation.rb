# An invitation, by email, for someone outside the aircraft (a mechanic) to
# sign one logbook entry with their own account and certificate
# (AC 120-78B 3.2.8.11). The link works once and expires.
class SigningInvitation < ApplicationRecord
  VALID_FOR = 14.days

  belongs_to :logbook_entry
  belongs_to :invited_by, class_name: "User", optional: true
  belongs_to :user, optional: true

  attr_reader :token

  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  before_validation(on: :create) do
    @token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@token)
    self.expires_at ||= VALID_FOR.from_now
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  def self.find_usable(token) = where(token_digest: digest(token), used_at: nil).where("expires_at > ?", Time.current).first

  def aircraft = logbook_entry.aircraft
end

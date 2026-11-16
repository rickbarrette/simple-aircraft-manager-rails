# An invitation code: a link someone opens to create an account (or accept
# with the one they have) and get roles on aircraft. Made by administrators
# (Admin → Invitations, any aircraft) or by whoever manages an aircraft's
# people (its Access page, that aircraft). Limited by number of uses, an
# expiry, and optionally to one email address; it can be revoked. Only a
# digest of the code is kept, so the link is shown once, when it's made.
#
# New accounts are only ever made by an administrator or from an
# administrator's invitation: anyone can add an aircraft and so manage its
# people, so other invitations are for people who already have an account.
class AccessInvitation < ApplicationRecord
  VALID_FOR = 14.days

  belongs_to :created_by, class_name: "User", optional: true
  has_many :grants, class_name: "AccessInvitationRole", dependent: :delete_all
  has_many :redemptions, class_name: "AccessInvitationRedemption", dependent: :delete_all
  has_many :aircraft, through: :grants

  attr_reader :token

  normalizes :email, with: ->(email) { email.strip.downcase.presence }
  normalizes :label, :name, with: ->(text) { text.squish.presence }
  validates :label, presence: true, length: { maximum: 100 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :max_uses, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }, allow_nil: true
  before_validation(on: :create) do
    @token = SecureRandom.urlsafe_base64(24)
    self.token_digest = self.class.digest(@token)
  end

  scope :recent_first, -> { order(created_at: :desc) }
  scope :usable, -> {
    where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current).where("max_uses IS NULL OR uses_count < max_uses")
  }

  # A new invitation by creator giving roles ([[aircraft, role], …]); its
  # link is emailed when it's for one address and email is set up.
  def self.create_for(creator, attributes, grants)
    invitation = new(attributes.merge(created_by: creator))
    grants.each { |aircraft, role| invitation.grants.build(aircraft: aircraft, role: role) }
    if invitation.save && invitation.email && MailSettings.configured?
      AccessInvitationMailer.invite(invitation, invitation.token).deliver_later
    end
    invitation
  end

  # "N12345: Mechanic. N54321: already Owner, unchanged" (from #redeem!).
  def self.describe(results)
    results.map { |aircraft, role, message| "#{aircraft.tail_number}: #{[ role&.name, message ].compact.join(', ')}" }.join(" ")
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  def self.find_by_token(token) = token.present? ? find_by(token_digest: digest(token)) : nil

  def usable? = !revoked? && !expired? && !used_up?
  # Whether someone without an account can make one with it (see above),
  # decided when it's used: its creator must still be an administrator.
  def creates_accounts? = created_by.present? && created_by.admin? && !created_by.disabled?
  def for_email?(email) = self.email.nil? || self.email == email.to_s.strip.downcase
  def revoked? = revoked_at.present?
  def expired? = expires_at.present? && expires_at <= Time.current
  def used_up? = max_uses.present? && uses_count >= max_uses
  def for?(user) = for_email?(user.email_address)
  def redeemed_by?(user) = redemptions.exists?(user: user)

  # Gives the person the invitation's roles, as if its creator added them
  # (AircraftAccess: so it can't give more than they could, then or now).
  # A role they already have on an aircraft stays as it is. Returns
  # [[aircraft, role or nil, message or nil], …].
  def redeem!(user)
    with_lock do
      raise ActiveRecord::RecordInvalid, self unless usable? && for?(user)
      redemptions.create!(user: user)
      increment!(:uses_count)
      grants.includes(:aircraft, :role).map do |grant|
        if (existing = grant.aircraft.roles.find_by(user: user))
          [ grant.aircraft, nil, I18n.t("models.access_invitation.already_has", role: existing.role.name) ]
        elsif created_by.nil? || created_by.disabled? || !created_by.can?(:manage_people, grant.aircraft)
          [ grant.aircraft, nil, I18n.t("models.access_invitation.creator_gone") ]
        else
          error = AircraftAccess.new(grant.aircraft, actor: created_by).add(user, grant.role)
          [ grant.aircraft, (grant.role unless error), error ]
        end
      end
    end
  end
end

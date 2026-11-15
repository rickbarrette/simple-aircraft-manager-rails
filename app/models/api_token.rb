# A key for the REST API (docs/api.md). Only its SHA-256 digest is kept; the
# token itself is shown once, when it's made.
#
# personal:    acts as its owner, with exactly their aircraft and role.
# integration: made by an admin for another system (e.g. Redmine), limited to
#              chosen aircraft and scopes. Its writes name the person they're
#              for (SAM-On-Behalf-Of), so the record history always shows who.
class ApiToken < ApplicationRecord
  KINDS = %w[personal integration].freeze
  SCOPES = LabelSet.new("api_token.scopes", %w[read squawks:write drafts:write])
  PREFIX = "sam_"

  belongs_to :user
  has_many :webhook_endpoints, dependent: :destroy
  has_many :idempotency_keys, class_name: "ApiIdempotencyKey", dependent: :delete_all

  attr_reader :token # the plain token, only right after create

  normalizes :name, with: ->(n) { n.to_s.strip }
  validates :name, presence: true, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validate :scopes_known
  validate :integration_made_by_admin, on: :create

  before_validation :generate, on: :create

  scope :active, -> { where(revoked_at: nil) }
  scope :personal, -> { where(kind: "personal") }
  scope :integration, -> { where(kind: "integration") }

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

  # The token for this string, if it's in use (and its owner is too).
  def self.authenticate(token)
    return unless token.to_s.start_with?(PREFIX)
    found = active.includes(:user).find_by(token_digest: digest(token))
    found if found && (found.integration? || !found.user.disabled?)
  end

  def personal? = kind == "personal"
  def integration? = kind == "integration"
  def revoked? = revoked_at.present?
  def revoke! = update!(revoked_at: Time.current)
  def allows?(scope) = scopes.include?(scope.to_s)

  # The aircraft this token reaches, acting for `user` (who must also have
  # access, for an integration acting on someone's behalf).
  def aircraft_scope(acting_user)
    if personal?
      user.accessible_aircraft
    else
      reachable = Aircraft.where(id: Array(aircraft_ids))
      acting_user ? reachable.where(id: acting_user.accessible_aircraft.select(:id)) : reachable
    end
  end

  # Last use, at most once a minute (no write per request).
  def used!(ip)
    return if last_used_at && last_used_at > 1.minute.ago && last_used_ip == ip
    update_columns(last_used_at: Time.current, last_used_ip: ip)
  end

  private

  def generate
    @token = "#{PREFIX}#{SecureRandom.base58(40)}"
    self.token_digest = self.class.digest(@token)
    self.token_hint = @token.first(PREFIX.length + 6)
    self.scopes = Array(scopes).map(&:to_s).compact_blank.uniq
  end

  def scopes_known
    errors.add(:scopes, :blank) if scopes.blank?
    errors.add(:scopes, :inclusion) if (Array(scopes) - SCOPES.keys).any?
  end

  def integration_made_by_admin
    errors.add(:kind, :admins_only) if integration? && !user&.admin?
  end
end

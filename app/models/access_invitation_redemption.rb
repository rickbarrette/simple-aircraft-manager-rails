# Who used an invitation, and when (once per person).
class AccessInvitationRedemption < ApplicationRecord
  belongs_to :access_invitation
  belongs_to :user

  validates :user_id, uniqueness: { scope: :access_invitation_id }
end

# A role an invitation gives on one aircraft.
class AccessInvitationRole < ApplicationRecord
  belongs_to :access_invitation
  belongs_to :aircraft
  belongs_to :role

  validates :aircraft_id, uniqueness: { scope: :access_invitation_id }
end

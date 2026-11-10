# An AD published in the Federal Register that may apply to an aircraft,
# waiting for the owner to track it (as an AD to comply with) or dismiss it.
class AdAlert < ApplicationRecord
  STATUSES = %w[new tracked dismissed].freeze

  belongs_to :aircraft
  belongs_to :component, optional: true
  belongs_to :airworthiness_directive, optional: true

  validates :fr_document_number, presence: true, uniqueness: { scope: :aircraft_id }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "new").order(publication_date: :desc) }

  # Tracks it: the AD (shared across aircraft, matched by number) is linked
  # to this aircraft, so it counts against airworthiness until complied with.
  def track!
    transaction do
      ad = AirworthinessDirective.find_by(name: ad_number) if ad_number.present?
      ad ||= AirworthinessDirective.create!(
        name: ad_number.presence || fr_document_number, short_description: summary, effective_date: effective_on,
        document_url: html_url, docket_number: amendment, required_action: abstract.to_s.truncate(2000)
      )
      # Matched on an installed component: the AD applies to that component;
      # otherwise to the airframe.
      if component && component.aircraft_id == aircraft_id
        ad.components << component unless ad.components.include?(component)
      else
        ad.aircraft << aircraft unless ad.aircraft.include?(aircraft)
      end
      update!(status: "tracked", airworthiness_directive: ad)
      ad
    end
  end

  def dismiss! = update!(status: "dismissed")

  # "Requires …" from the abstract, else the title without its prefix.
  def summary
    requires = abstract.to_s[/This AD requires ([^.]+)\./, 1]
    (requires ? "Requires #{requires}" : title.to_s.delete_prefix("Airworthiness Directives; ")).truncate(250)
  end
end

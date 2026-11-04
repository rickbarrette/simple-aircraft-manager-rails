# Raised when a flight-activity write is attempted on a RED aircraft whose
# airworthiness enforcement is enabled.
class AircraftGroundedError < StandardError
  attr_reader :airworthiness

  def initialize(airworthiness)
    @airworthiness = airworthiness
    reasons = airworthiness.red_issues.map(&:title).join("; ")
    super([ "Aircraft is grounded and airworthiness enforcement is enabled", reasons.presence ].compact.join(": "))
  end
end

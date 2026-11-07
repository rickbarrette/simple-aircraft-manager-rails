# The recurring inspections and checks Part 91 calls for, to add to an
# aircraft in one go (Inspections → Standard inspections).
module StandardInspections
  Template = Data.define(:key, :name, :who, :months, :days, :hours, :tolerance, :effect, :checked, :pattern) do
    def attributes
      { name: name, recurring: true, recurring_months: months.to_i, recurring_days: days.to_i,
        recurring_hours: hours.to_i, hours_tolerance: tolerance.to_i, effect: effect }
    end
  end

  TEMPLATES = [
    Template.new(key: "annual", name: "Annual inspection (91.409(a))", who: "Every aircraft",
                 months: 12, days: nil, hours: nil, tolerance: nil, effect: "grounds", checked: true, pattern: /annual/i),
    Template.new(key: "hundred", name: "100-hour inspection (91.409(b))", who: "Carrying anyone for hire, or flight instruction for hire",
                 months: nil, days: nil, hours: 100, tolerance: 10, effect: "grounds", checked: false, pattern: /100[- ]?h(ou)?r/i),
    Template.new(key: "transponder", name: "Transponder check (91.413)", who: "Aircraft with a transponder",
                 months: 24, days: nil, hours: nil, tolerance: nil, effect: "no_transponder", checked: true, pattern: /transponder|91\.413/i),
    Template.new(key: "pitot_static", name: "Altimeter and static system check (91.411)", who: "Flying IFR in controlled airspace",
                 months: 24, days: nil, hours: nil, tolerance: nil, effect: "no_ifr", checked: false, pattern: /pitot|static|altimeter|91\.411/i),
    Template.new(key: "elt", name: "ELT inspection (91.207(d))", who: "Aircraft required to carry an ELT",
                 months: 12, days: nil, hours: nil, tolerance: nil, effect: "grounds", checked: true, pattern: /\belt\b|91\.207/i),
    Template.new(key: "vor", name: "VOR check (91.171)", who: "Flying IFR using VORs; the pilot may do and log it",
                 months: nil, days: 30, hours: nil, tolerance: nil, effect: "no_ifr", checked: false, pattern: /\bvor\b|91\.171/i)
  ].freeze

  module_function

  def find(key) = TEMPLATES.find { _1.key == key }

  # The aircraft's existing inspection type a template matches, if any.
  def existing_for(template, aircraft)
    aircraft.applicable_inspection_types.find { _1.name.match?(template.pattern) }
  end

  # Adds the chosen templates the aircraft doesn't already track. Returns the
  # inspection types added.
  def add!(aircraft, keys)
    added = {}
    InspectionType.transaction do
      Array(keys).filter_map { find(_1.to_s) }.each do |t|
        next if existing_for(t, aircraft)
        type = InspectionType.find_by(name: t.name) || InspectionType.create!(t.attributes)
        type.aircraft << aircraft unless type.aircraft.include?(aircraft)
        added[t.key] = type
      end
      # An annual also counts as the 100-hour (91.409(b)).
      annual = added["annual"] || (find("annual") && existing_for(find("annual"), aircraft))
      hundred = added["hundred"] || existing_for(find("hundred"), aircraft)
      annual.update!(satisfies: hundred) if annual && hundred && annual.satisfies_id.nil? && (added["annual"] || added["hundred"])
    end
    added.values
  end
end

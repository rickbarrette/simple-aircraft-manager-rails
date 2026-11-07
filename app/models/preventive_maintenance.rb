# Logbook wording for common preventive maintenance a pilot-owner may do
# (14 CFR 43.3(g)), keyed to Part 43 Appendix A paragraph (c). The item
# descriptions are paraphrased; the rule sets each item's limits.
module PreventiveMaintenance
  Item = Data.define(:key, :paragraphs, :label, :work)

  ITEMS = [
    Item.new("oil_change", %w[(c)(6) (c)(23)], "Oil and filter change", "Drained engine oil and replaced the oil filter. Cut open and inspected the filter: no metal found. Refilled with __ qt of __. Ran engine and checked for leaks."),
    Item.new("tire", %w[(c)(1)], "Tire removal, installation or repair", "Removed and replaced the __ tire and tube. Inflated to __ psi."),
    Item.new("strut", %w[(c)(3)], "Servicing landing gear shock struts", "Serviced the __ shock strut with __."),
    Item.new("bearings", %w[(c)(4)], "Servicing wheel bearings", "Cleaned, inspected and repacked the __ wheel bearings with __ grease."),
    Item.new("safety_wire", %w[(c)(5)], "Replacing safety wire or cotter keys", "Replaced defective safety wire / cotter key at __."),
    Item.new("lubrication", %w[(c)(6)], "Lubrication", "Lubricated __ per the maintenance manual."),
    Item.new("hydraulic", %w[(c)(8)], "Replenishing hydraulic fluid", "Replenished the hydraulic reservoir with __."),
    Item.new("upholstery", %w[(c)(11)], "Repairing upholstery", "Repaired the upholstery of __."),
    Item.new("fairings", %w[(c)(12)], "Small repairs to fairings or cowlings", "Made a small repair to the __ (non-structural, contour unchanged)."),
    Item.new("seat_belts", %w[(c)(14)], "Replacing safety belts", "Replaced the __ safety belt with P/N __."),
    Item.new("landing_light_wiring", %w[(c)(16)], "Repairing landing light circuits", "Troubleshot and repaired a broken circuit in the landing light wiring."),
    Item.new("lights", %w[(c)(17)], "Replacing light bulbs, reflectors or lenses", "Replaced the __ position/landing light bulb with P/N __. Checked operation."),
    Item.new("cowling", %w[(c)(19)], "Replacing a cowling", "Removed and reinstalled the __ cowling."),
    Item.new("spark_plugs", %w[(c)(20)], "Cleaning or replacing spark plugs", "Removed, cleaned, gapped and rotated the spark plugs. Reinstalled and torqued to __."),
    Item.new("hoses", %w[(c)(21)], "Replacing hose connections (not hydraulic)", "Replaced the __ hose with P/N __."),
    Item.new("fuel_lines", %w[(c)(22)], "Replacing prefabricated fuel lines", "Replaced the prefabricated fuel line __ with P/N __."),
    Item.new("filters", %w[(c)(23)], "Cleaning or replacing fuel/oil strainers or filters", "Cleaned / replaced the __ strainer / filter element."),
    Item.new("battery", %w[(c)(24)], "Replacing or servicing the battery", "Replaced the battery with P/N __ / serviced the battery."),
    Item.new("fasteners", %w[(c)(26)], "Replacing non-structural fasteners", "Replaced non-structural standard fasteners at __."),
    Item.new("chip_detector", %w[(c)(29)], "Checking magnetic chip detectors", "Removed, checked and reinstalled the magnetic chip detector: no particles found."),
    Item.new("nav_database", %w[(c)(31)], "Updating the navigation database", "Updated the __ navigation database to cycle __."),
    Item.new("nav_com", %w[(c)(32)], "Swapping a tray-mounted nav/com unit", "Removed and reinstalled the tray-mounted __ unit. Checked operation.")
  ].freeze

  module_function

  def text_for(item)
    "#{item.work} Preventive maintenance per 14 CFR 43.3(g), Part 43 Appendix A paragraph #{item.paragraphs.to_sentence}."
  end
end

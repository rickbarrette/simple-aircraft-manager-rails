# Two built-in logbook templates cited the wrong rule. A tray-mounted nav/com
# swap is Part 43 Appendix A (c)(31), not (c)(32) (which doesn't exist), and a
# navigation database update isn't preventive maintenance at all: 14 CFR
# 43.3(k) says it isn't maintenance. Copies already in the database are fixed
# where an admin hasn't changed their text; edited ones are left alone.
class FixAvionicsTemplateCitations < ActiveRecord::Migration[8.1]
  class Template < ActiveRecord::Base
    self.table_name = "logbook_templates"
  end

  FIXES = [
    { name: "Swapping a tray-mounted nav/com unit",
      old_reference: "Part 43 App. A (c)(32)",
      old_text: "Removed and reinstalled the tray-mounted __ unit. Checked operation. Preventive maintenance per 14 CFR 43.3(g), Part 43 Appendix A paragraph (c)(32).",
      new: { reference: "Part 43 App. A (c)(31)",
             text: "Removed and reinstalled the self-contained, panel-mounted, tray-mounted __ unit per the manufacturer's instructions. Performed an operational check before use. Preventive maintenance per 14 CFR 43.3(g), Part 43 Appendix A paragraph (c)(31)." } },
    { name: "Updating the navigation database",
      old_reference: "Part 43 App. A (c)(31)",
      old_text: "Updated the __ navigation database to cycle __. Preventive maintenance per 14 CFR 43.3(g), Part 43 Appendix A paragraph (c)(31).",
      new: { reference: "14 CFR 43.3(k)",
             text: "Updated the __ navigation database to cycle __ from the flight deck, per the manufacturer's instructions, without tools or disassembly. Database update under 14 CFR 43.3(k); not maintenance.",
             entry_type: "OTHER", certificate_type: nil } }
  ].freeze

  def up
    FIXES.each do |fix|
      Template.where(name: fix[:name], reference: fix[:old_reference], text: fix[:old_text]).update_all(fix[:new].merge(updated_at: Time.current))
    end
  end

  def down
    FIXES.each do |fix|
      Template.where(name: fix[:name], reference: fix[:new][:reference], text: fix[:new][:text])
              .update_all(reference: fix[:old_reference], text: fix[:old_text], entry_type: "MAINTENANCE", certificate_type: "PILOT", updated_at: Time.current)
    end
  end
end

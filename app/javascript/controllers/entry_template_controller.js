import { Controller } from "@hotwired/stimulus"

// Fills a new logbook entry from a preventive maintenance template: the
// wording, the entry type, and "pilot" as the kind of certificate unless one
// is already chosen.
export default class extends Controller {
  static targets = [ "template", "text", "entryType", "certificate" ]

  apply() {
    const option = this.templateTarget.selectedOptions[0]
    if (!option?.dataset.text) return
    if (this.textTarget.value.trim() && !confirm("Replace the entry text with this template?")) return
    this.textTarget.value = option.dataset.text
    if (this.hasEntryTypeTarget) this.entryTypeTarget.value = "MAINTENANCE"
    if (this.hasCertificateTarget && !this.certificateTarget.value) this.certificateTarget.value = "PILOT" // keep a chosen certificate
    this.textTarget.focus()
  }
}

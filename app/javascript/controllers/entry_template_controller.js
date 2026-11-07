import { Controller } from "@hotwired/stimulus"

// Fills a new logbook entry from a template: the wording, and when the
// template sets them, the entry type, the logbook (which also picks the
// matching component) and the kind of certificate, unless one is chosen.
export default class extends Controller {
  static targets = [ "template", "text", "entryType", "logType", "certificate" ]

  apply() {
    const option = this.templateTarget.selectedOptions[0]
    if (!option?.dataset.text) return
    if (this.textTarget.value.trim() && !confirm("Replace the entry text with this template?")) return
    const { text, entryType, logType, certificate } = option.dataset
    this.textTarget.value = text
    if (entryType && this.hasEntryTypeTarget) this.entryTypeTarget.value = entryType
    if (logType && this.hasLogTypeTarget && this.logTypeTarget.value !== logType) {
      this.logTypeTarget.value = logType
      this.logTypeTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
    if (certificate && this.hasCertificateTarget && !this.certificateTarget.value) this.certificateTarget.value = certificate
    this.textTarget.focus()
  }
}

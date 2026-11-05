import { Controller } from "@hotwired/stimulus"
import { nextDue, describeDue } from "next_due"

// Live next-due preview (and prefill of an AD's next-due tach reading) from
// the selected AD/inspection type's recurrence rule.
//
//   data-controller="next-due" data-next-due-rules-value='{"12": {"hours": 100, "months": 12, "days": 0}}'
//   targets: rule (select), date, hours, dueHours (optional), permanent (optional), preview
export default class extends Controller {
  static targets = ["rule", "date", "hours", "dueHours", "permanent", "preview"]
  static values = { rules: Object }

  connect() {
    // Don't overwrite a reading that's already filled in (e.g. editing a record).
    this.manual = this.hasDueHoursTarget && parseFloat(this.dueHoursTarget.value) > 0
    this.recalc()
  }

  // The user typed their own next-due reading: stop overwriting it.
  markManual() {
    this.manual = this.dueHoursTarget.value.trim() !== "" && parseFloat(this.dueHoursTarget.value) > 0
    this.renderPreview()
  }

  // Inputs that the rule depends on changed: recompute, unless overridden.
  changed() {
    this.manual = false
    this.recalc()
  }

  recalc() {
    const due = this.computeDue()
    if (this.hasDueHoursTarget && !this.manual && !this.isPermanent) {
      this.dueHoursTarget.value = due.hours != null ? due.hours.toFixed(1) : "0"
    }
    this.renderPreview(due)
  }

  renderPreview(due = this.computeDue()) {
    if (!this.hasPreviewTarget) return
    const rule = this.currentRule
    let text
    if (this.isPermanent) text = "Permanent compliance: never due again."
    else if (!this.ruleTarget.value) text = ""
    else if (!rule) text = "One-time: no recurring due date."
    else {
      if (this.hasDueHoursTarget && this.manual) due = { ...due, hours: parseFloat(this.dueHoursTarget.value) }
      text = describeDue(due) ? `Next due: ${describeDue(due)}` : "Enter the date and hours to calculate the next due."
    }
    this.previewTarget.textContent = text
    this.previewTarget.hidden = text === ""
  }

  computeDue() {
    return nextDue(this.currentRule, this.dateTarget.value, this.hoursTarget.value)
  }

  get currentRule() {
    return this.rulesValue[this.ruleTarget.value] || null
  }

  get isPermanent() {
    return this.hasPermanentTarget && this.permanentTarget.checked
  }
}

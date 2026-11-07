import { Controller } from "@hotwired/stimulus"

// Logbook entry form: picking an engine or propeller log selects that
// component (if none is chosen yet), and picking a component fills in its
// current total time and time since overhaul.
export default class extends Controller {
  static targets = [ "logType", "component", "total", "since" ]

  logTypeChanged() {
    if (this.componentTarget.value) return
    const kind = this.logTypeTarget.value
    const match = [ ...this.componentTarget.options ].find((o) => o.dataset.kind && o.dataset.kind === kind)
    if (match) {
      this.componentTarget.value = match.value
      this.componentChanged()
    }
  }

  componentChanged() {
    const option = this.componentTarget.selectedOptions[0]
    if (!option?.dataset.total) return
    this.totalTarget.value = option.dataset.total
    this.sinceTarget.value = option.dataset.since
  }
}

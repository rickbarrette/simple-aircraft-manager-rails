import { Controller } from "@hotwired/stimulus"

// Logbook entry form: picking an engine or propeller log selects that
// component (if none is chosen yet), and the component's total time and time
// since overhaul are filled in for the airframe time entered: its current
// times, shifted by however far the entry's airframe time is from the
// aircraft's current time. Typing in the component times yourself stops the
// automatic updates (until another component is picked).
export default class extends Controller {
  static targets = [ "logType", "component", "total", "since", "airframe" ]
  static values = { aircraftHours: Number }

  connect() { this.manual = false }

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
    this.manual = false
    this.recompute()
  }

  airframeChanged() {
    if (!this.manual) this.recompute()
  }

  markManual() { this.manual = true }

  recompute() {
    const option = this.componentTarget.selectedOptions[0]
    if (!option?.dataset.total) return
    const airframe = this.hasAirframeTarget ? parseFloat(this.airframeTarget.value) : NaN
    const delta = Number.isNaN(airframe) ? 0 : airframe - this.aircraftHoursValue
    const total = parseFloat(option.dataset.total) + delta
    const since = parseFloat(option.dataset.since) + delta
    // Negative means the entry is from before the component was new or overhauled: unknown.
    this.totalTarget.value = total >= 0 ? total.toFixed(1) : ""
    this.sinceTarget.value = since >= 0 ? since.toFixed(1) : ""
  }
}

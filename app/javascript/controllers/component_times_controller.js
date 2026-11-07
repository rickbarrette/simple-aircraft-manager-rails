import { Controller } from "@hotwired/stimulus"

// Logbook entry form: picking an engine or propeller log selects that
// component (if none is chosen yet), and the component's total time and time
// since overhaul are filled in for the airframe time entered: its current
// times, shifted by however far the entry's airframe time is from the
// aircraft's current time. Typing in the component times yourself stops the
// automatic updates (until another component is picked). The chosen
// component's sub-components (oil filter…) can be ticked to include them,
// with their times worked out the same way.
export default class extends Controller {
  static targets = [ "logType", "component", "total", "since", "airframe", "partsBox", "part" ]
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
    this.showParts()
    this.recompute()
  }

  // Only the chosen component's sub-components are offered.
  showParts() {
    const id = this.componentTarget.value
    let any = false
    this.partTargets.forEach((row) => {
      const mine = id && row.dataset.ancestors.split(" ").includes(id)
      row.hidden = !mine
      if (!mine) row.querySelector("input[type=checkbox]").checked = false
      any ||= mine
    })
    if (this.hasPartsBoxTarget) this.partsBoxTarget.hidden = !any
  }

  partToggled(event) {
    const row = event.target.closest("[data-component-times-target=part]")
    if (event.target.checked) { delete row.dataset.manual; this.fillPart(row) }
  }

  partEdited(event) {
    const row = event.target.closest("[data-component-times-target=part]")
    row.dataset.manual = "true"
    row.querySelector("input[type=checkbox]").checked = true
  }

  airframeChanged() {
    if (!this.manual) this.recompute()
    this.partTargets.forEach((row) => { if (!row.hidden && !row.dataset.manual) this.fillPart(row) })
  }

  get delta() {
    const airframe = this.hasAirframeTarget ? parseFloat(this.airframeTarget.value) : NaN
    return Number.isNaN(airframe) ? 0 : airframe - this.aircraftHoursValue
  }

  fillPart(row) {
    const total = parseFloat(row.dataset.total) + this.delta
    const since = parseFloat(row.dataset.since) + this.delta
    row.querySelector("[data-role=hours]").value = total >= 0 ? total.toFixed(1) : ""
    row.querySelector("[data-role=since]").value = since >= 0 ? since.toFixed(1) : ""
  }

  markManual() { this.manual = true }

  recompute() {
    const option = this.componentTarget.selectedOptions[0]
    if (!option?.dataset.total) return
    const total = parseFloat(option.dataset.total) + this.delta
    const since = parseFloat(option.dataset.since) + this.delta
    // Negative means the entry is from before the component was new or overhauled: unknown.
    this.totalTarget.value = total >= 0 ? total.toFixed(1) : ""
    this.sinceTarget.value = since >= 0 ? since.toFixed(1) : ""
  }
}

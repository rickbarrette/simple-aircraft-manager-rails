import { Controller } from "@hotwired/stimulus"
import { queue, formFields, newKey } from "controllers/offline_queue"

// The Log Flight form: with no connection, the flight is kept on this device
// and sent later (see offline_sync_controller). The next leg starts where the
// last saved one ended.
export default class extends Controller {
  static targets = [ "key", "notice" ]
  static values = { tail: String }

  async connect() {
    if (!this.keyTarget.value) this.keyTarget.value = newKey()
    try {
      const mine = (await queue.all()).filter((i) => i.url === this.element.action)
      if (mine.length) {
        this.prefillFrom(mine[mine.length - 1])
        this.say(`${mine.length} flight${mine.length > 1 ? "s" : ""} logged offline on this device, waiting to send. This one starts where the last ended.`)
      }
    } catch (_) { /* no IndexedDB: nothing queued */ }
    this.rememberForm()
  }

  // No connection: keep it here instead of submitting.
  async submit(event) {
    if (navigator.onLine) return
    event.preventDefault()
    event.stopImmediatePropagation()
    await this.save(formFields(this.element))
  }

  // Kept in case the request fails on the way (no signal but the browser thinks it's online).
  remember() { this.pending = formFields(this.element) }

  async networkFailed() {
    if (this.pending) await this.save(this.pending)
  }

  // A proxy answered because the app is unreachable (502/503/504): keep the
  // flight instead of showing the proxy's error page.
  async gatewayFailed(event) {
    if (![ 502, 503, 504 ].includes(event.detail.fetchResponse.statusCode) || !this.pending) return
    event.preventDefault()
    await this.save(this.pending)
  }

  async save(fields) {
    const item = { id: this.keyTarget.value, url: this.element.action, tail: this.tailValue, savedAt: new Date().toISOString(), fields }
    try {
      await queue.add(item)
    } catch (_) {
      this.say("No connection, and this browser can't store the flight. Write it down and log it when you're back online.")
      return
    }
    this.prefillFrom(item)
    this.clearLegFields()
    this.keyTarget.value = newKey()
    this.pending = null
    window.scrollTo({ top: 0 })
    this.say("No connection: flight saved on this device. It's sent automatically when you're back online. Log the next leg below, or close the app.")
    document.dispatchEvent(new CustomEvent("offline-queue:changed"))
  }

  prefillFrom(item) {
    const value = (name) => (item.fields.find(([ n ]) => n === `flight_log[${name}]`) || [])[1]
    const set = (name, v) => { const el = this.element.querySelector(`[name="flight_log[${name}]"]`); if (el && v) el.value = v }
    set("tach_out", value("tach_in"))
    set("hobbs_out", value("hobbs_in"))
    set("departure_location", value("destination_location"))
  }

  clearLegFields() {
    for (const name of [ "tach_in", "tach_time", "hobbs_in", "hobbs_time", "destination_location", "route", "notes",
      "oil_added", "oil_level_after", "fuel_added", "fuel_level_after", "track_log", "engine_data" ]) {
      const el = this.element.querySelector(`[name="flight_log[${name}]"]`)
      if (el) el.value = ""
    }
  }

  // Lets the offline page offer this form for this aircraft.
  rememberForm() {
    try {
      const forms = JSON.parse(localStorage.getItem("sam-offline-forms") || "{}")
      forms[location.pathname] = this.tailValue
      localStorage.setItem("sam-offline-forms", JSON.stringify(forms))
    } catch (_) { /* storage off */ }
  }

  say(text) {
    this.noticeTarget.textContent = text
    this.noticeTarget.classList.remove("hidden")
  }
}

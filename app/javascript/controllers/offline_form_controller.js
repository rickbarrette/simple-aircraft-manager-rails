import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"
import { queue, formFields, newKey, currentUser } from "controllers/offline_queue"

// Log Flight and Report Squawk: with no connection, the form is kept on this
// device and sent later (see offline_sync_controller). For flights, the next
// leg starts where the last saved one ended.
export default class extends Controller {
  static targets = [ "key", "notice" ]
  static values = { kind: { type: String, default: "flight" }, tail: String }

  async connect() {
    if (!this.keyTarget.value) this.keyTarget.value = newKey()
    try {
      const mine = (await queue.mine()).filter((i) => i.url === this.element.action)
      if (mine.length) {
        if (this.flight) this.prefillFrom(mine[mine.length - 1])
        this.say(t(`offline.${this.kindValue}.queued_here`, { count: mine.length }))
      }
    } catch (_) { /* no IndexedDB: nothing queued */ }
    this.rememberForm()
  }

  get flight() { return this.kindValue === "flight" }

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

  // A proxy answered because the app is unreachable (502/503/504): keep it
  // instead of showing the proxy's error page.
  async gatewayFailed(event) {
    if (![ 502, 503, 504 ].includes(event.detail.fetchResponse.statusCode) || !this.pending) return
    event.preventDefault()
    await this.save(this.pending)
  }

  async save(fields) {
    const item = { id: this.keyTarget.value, kind: this.kindValue, url: this.element.action, tail: this.tailValue,
                   user: currentUser(), savedAt: new Date().toISOString(), fields }
    try {
      await queue.add(item)
    } catch (_) {
      this.say(t(`offline.${this.kindValue}.no_storage`))
      return
    }
    if (this.flight) this.prefillFrom(item)
    this.clearFields()
    this.keyTarget.value = newKey()
    this.pending = null
    window.scrollTo({ top: 0 })
    this.say(t(`offline.${this.kindValue}.saved_on_device`))
    document.dispatchEvent(new CustomEvent("offline-queue:changed"))
  }

  prefillFrom(item) {
    const value = (name) => (item.fields.find(([ n ]) => n === `flight_log[${name}]`) || [])[1]
    const set = (name, v) => { const el = this.element.querySelector(`[name="flight_log[${name}]"]`); if (el && v) el.value = v }
    set("tach_out", value("tach_in"))
    set("hobbs_out", value("hobbs_in"))
    set("departure_location", value("destination_location"))
  }

  clearFields() {
    const names = this.flight
      ? [ "tach_in", "tach_time", "hobbs_in", "hobbs_time", "destination_location", "route", "notes",
          "oil_added", "oil_level_after", "fuel_added", "fuel_level_after", "track_log", "engine_data" ].map((n) => `flight_log[${n}]`)
      : [ "squawk[issue_reported]", "squawk[attachments][]" ]
    for (const name of names) {
      const el = this.element.querySelector(`[name="${name}"]`)
      if (el) el.value = ""
    }
  }

  // Lets the offline page and the home-screen shortcuts offer this form.
  rememberForm() {
    try {
      const forms = JSON.parse(localStorage.getItem("sam-offline-forms") || "{}")
      forms[location.pathname] = { tail: this.tailValue, kind: this.kindValue }
      localStorage.setItem("sam-offline-forms", JSON.stringify(forms))
    } catch (_) { /* storage off */ }
  }

  say(text) {
    this.noticeTarget.textContent = text
    this.noticeTarget.classList.remove("hidden")
  }
}

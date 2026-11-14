import { Controller } from "@hotwired/stimulus"

// A card that can be hidden for good on this device (e.g. the setup checklist).
export default class extends Controller {
  static values = { key: String }

  connect() {
    try { if (localStorage.getItem(this.keyValue)) this.element.hidden = true } catch (_) { /* storage off */ }
  }

  hide() {
    try { localStorage.setItem(this.keyValue, "1") } catch (_) { /* storage off */ }
    this.element.hidden = true
  }
}

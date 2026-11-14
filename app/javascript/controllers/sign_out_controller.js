import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"
import { queue } from "controllers/offline_queue"

// Signing out clears what this device kept for working offline (forms and
// page copies with aircraft details). Unsent flights and squawks stay, tagged
// with their user, and are sent the next time that person signs in here.
export default class extends Controller {
  async clean(event) {
    if (this.cleaned) return
    event.preventDefault()
    try {
      const unsent = (await queue.mine()).length
      if (unsent && !confirm(t("sign_out.unsent", { count: unsent }))) return
    } catch (_) { /* no IndexedDB */ }
    try { await Promise.all([ "sam-forms", "sam-pages", "sam-images", "sam-flight-forms" ].map((name) => caches.delete(name))) } catch (_) { /* no Cache API */ }
    try { [ "sam-offline-forms", "sam-offline-prep" ].forEach((key) => localStorage.removeItem(key)) } catch (_) { /* storage off */ }
    try { navigator.clearAppBadge?.() } catch (_) { /* not supported */ }
    this.cleaned = true
    this.element.requestSubmit()
  }
}

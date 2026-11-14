import { Controller } from "@hotwired/stimulus"
import { t, locale } from "i18n"

// Pages the service worker kept for use without a connection (an aircraft's
// overview and weight and balance, and the Log Flight / Report Squawk forms)
// say when they were saved when they're shown from that copy.
const STALE_AFTER = 5 * 60 * 1000

export default class extends Controller {
  static targets = [ "banner" ]

  connect() {
    const rendered = Date.parse(document.querySelector("meta[name=rendered-at]")?.content || "")
    const stale = rendered && Date.now() - rendered > STALE_AFTER
    if (stale) {
      const when = new Date(rendered).toLocaleString(locale(), { dateStyle: "medium", timeStyle: "short" })
      this.bannerTarget.textContent = t("offline.saved_copy", { time: when })
    }
    this.bannerTarget.classList.toggle("hidden", !stale)
  }
}

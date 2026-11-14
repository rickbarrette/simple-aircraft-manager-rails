import { Controller } from "@hotwired/stimulus"
import { t, locale } from "i18n"

// Update Hours (Overview): confirms the new meter readings first, since they
// change every in-service component's hours and log no flight.
export default class extends Controller {
  static targets = [ "tach", "hobbs" ]
  static values = { tach: Number, hobbs: Number }

  confirm(event) {
    const lines = [ this.line("tach", this.tachValue, this.tachTarget.value),
                    this.hasHobbsTarget ? this.line("hobbs", this.hobbsValue, this.hobbsTarget.value) : null ].filter(Boolean)
    if (!lines.length) {
      event.preventDefault()
      return alert(t("hours.no_change"))
    }
    const lower = parseFloat(this.tachTarget.value) < this.tachValue
    const message = [ ...lines, "", t("hours.effect"), lower ? t("hours.lower") : null ].filter((l) => l !== null).join("\n")
    if (!confirm(message)) event.preventDefault()
  }

  // "Tach 4,211.6 → 4,213.0 (+1.4)", or null when unchanged or blank.
  line(meter, now, entered) {
    const value = parseFloat(entered)
    if (Number.isNaN(value) || Math.abs(value - now) < 0.05) return null
    const fmt = (n) => n.toLocaleString(locale(), { minimumFractionDigits: 1, maximumFractionDigits: 1 })
    const delta = value - now
    return t(`hours.${meter}`, { from: fmt(now), to: fmt(value), delta: `${delta > 0 ? "+" : "−"}${fmt(Math.abs(delta))}` })
  }
}

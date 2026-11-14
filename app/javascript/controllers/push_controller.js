import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Profile → This device: notifications on or off for this browser or app.
export default class extends Controller {
  static targets = [ "status", "on", "off", "test" ]
  static values = { key: String, url: String, testUrl: String }

  async connect() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window) || !("Notification" in window)) {
      const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
      return this.show(t(ios ? "push.ios_install_first" : "push.unsupported"), null)
    }
    this.registration = await navigator.serviceWorker.ready
    const subscription = await this.registration.pushManager.getSubscription()
    if (Notification.permission === "denied") return this.show(t("push.blocked"), null)
    if (!subscription) return this.show(t("push.off"), false)
    // The browser keeps its subscription even if the app never recorded it
    // (or forgot it), so record it again on every visit.
    const error = await this.save(subscription)
    this.show(error ? t("push.not_saved", { reason: error }) : t("push.on"), true)
  }

  async turnOn() {
    if (await Notification.requestPermission() !== "granted") return this.show(t("push.blocked"), null)
    let subscription
    try {
      subscription = await this.registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.keyBytes() })
    } catch (e) {
      return this.show(t("push.failed", { reason: e.message || e.name }), false)
    }
    const error = await this.save(subscription)
    this.show(error ? t("push.failed", { reason: error }) : t("push.on"), !error)
    if (error) await subscription.unsubscribe()
  }

  // Records the subscription with the app: null, or why it couldn't.
  async save(subscription) {
    try {
      const response = await this.request("POST", this.urlValue, { subscription: subscription.toJSON() })
      if (response.ok) return null
      return (await response.json().catch(() => ({}))).error || `HTTP ${response.status}`
    } catch (e) {
      return e.message
    }
  }

  async turnOff() {
    const subscription = await this.registration.pushManager.getSubscription()
    if (subscription) {
      await this.request("DELETE", this.urlValue, { endpoint: subscription.endpoint })
      await subscription.unsubscribe()
    }
    this.show(t("push.off"), false)
  }

  // Sends one to each of your devices and lists which push services took it.
  async sendTest() {
    this.statusTarget.textContent = t("push.test_sending")
    try {
      const { devices } = await (await this.request("POST", this.testUrlValue, {})).json()
      const lines = devices.length
        ? [ ...devices.map((d) => d.error ? t("push.test_failed", { device: d.device, reason: d.error }) : t("push.test_ok", { device: d.device })), t("push.test_hint") ]
        : [ t("push.test_none") ]
      this.statusTarget.textContent = lines.join("\n")
    } catch (e) {
      this.statusTarget.textContent = t("push.failed", { reason: e.message })
    }
  }

  // on: true / false, or null when it can't be changed here.
  show(text, on) {
    this.statusTarget.textContent = text
    this.onTarget.hidden = on !== false
    this.offTarget.hidden = on !== true
    this.testTarget.hidden = on !== true
  }

  request(method, url, body) {
    return fetch(url, { method, credentials: "same-origin", body: JSON.stringify(body),
                        headers: { "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" } })
  }

  keyBytes() {
    const base64 = (this.keyValue + "=".repeat((4 - this.keyValue.length % 4) % 4)).replace(/-/g, "+").replace(/_/g, "/")
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  }
}

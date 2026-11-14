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
    this.show(t(subscription ? "push.on" : "push.off"), !!subscription)
  }

  async turnOn() {
    if (await Notification.requestPermission() !== "granted") return this.show(t("push.blocked"), null)
    try {
      const subscription = await this.registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.keyBytes() })
      const response = await this.request("POST", this.urlValue, { subscription: subscription.toJSON() })
      if (!response.ok) throw new Error(response.status)
      this.show(t("push.on"), true)
    } catch (_) {
      this.show(t("push.failed"), false)
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

  async sendTest() {
    await this.request("POST", this.testUrlValue, {})
    this.statusTarget.textContent = t("push.test_sent")
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
